// ============================================================================
//  Composite_Batch.ijm
//  Batch export of flattened colour composites for high-content imaging
// ----------------------------------------------------------------------------
//  Version  : 1.0  (2026-11-05)
//  Requires : Fiji / ImageJ 1.53t or newer
// ----------------------------------------------------------------------------
//  WORKFLOW (4 dialogs)
//   1. Folders    : source folder (optionally with subfolders, e.g. plate\A01),
//                   destination folder, file extensions, number of channels.
//                   All files found are listed in the Log window.
//   2. Channels   : one text per channel (e.g. "DAPI"). A file belongs to a
//                   channel when its NAME contains that text. Files of the same
//                   field are grouped into a "set":
//                      A01_f01_DAPI.tif + A01_f01_GFP.tif  ->  set "A01_f01"
//                   (same folder + same name once the channel text is removed).
//                   A grouping check shows counts, an example set, and lets you
//                   go back and fix the texts.
//   3. Display    : one colour (LUT) and one FIXED min/max per channel, applied
//                   to every set so intensities stay comparable. Start values =
//                   last values used for that channel text, else auto-contrast
//                   of the first set. Two helpers, usable in any order/repeat:
//                    - Auto: auto-contrast (0.35 % saturated) on N random sets
//                      (default 20), then median or mean of their min and max.
//                      Fixed seed = same draw each time; sampled sets in Log.
//                    - Preview: opens a set so you can tune it with
//                      Brightness/Contrast; the values are read back.
//   4. Export     : format, name suffix, folder structure, overwrite, optional
//                   single-channel images, scale bar and burned-in label.
//                   A run log (settings + every file written or skipped) is
//                   saved in the destination folder.
//
//  RULES WORTH KNOWING
//   - Matching uses the file name only, not folder names.
//   - If several channel texts match one name, the one nearest the END of the
//     name wins; on a tie the longer text wins (so "EGFP" beats "GFP").
//   - Files matching no channel text are ignored (counted in the check).
//   - Images of one set must share size and bit depth (else the set is skipped
//     and reported). Stacks: only the first plane is used.
//   - Files are paired by NAME, not by sorted position, so a missing image
//     (e.g. empty well) cannot shift the pairing of the following ones.
//   - .tif/.tiff open directly; other formats (Cellomics .C01) via Bio-Formats
//     (bundled with Fiji).
//   - Source images are never modified. Settings are remembered between runs.
//
//  CHANGELOG
//   1.0  2026-11-05  First version.
// ============================================================================

requires("1.53t");

// ------------------------------------------------------------------ constants
var PREF       = "compbatch.";
var LUTS       = newArray("Blue", "Green", "Red", "Magenta", "Cyan", "Yellow", "Grays");
var DEF_TAGS   = newArray("DAPI", "GFP", "RFP", "Cy5", "Ch5", "Ch6", "Ch7");
var INCOMPLETE = newArray("Skip them", "Export with the channels present");
var FORMATS    = newArray("PNG (lossless, recommended)", "TIFF (RGB)", "JPEG (lossy)");
var FMT_TYPE   = newArray("PNG", "Tiff", "Jpeg");
var FMT_EXT    = newArray(".png", ".tif", ".jpg");
var COLORS     = newArray("White", "Black", "Light Gray", "Gray", "Dark Gray", "Red", "Green", "Blue", "Yellow");
var COLOR_HEX  = newArray("#ffffff", "#000000", "#c0c0c0", "#808080", "#404040", "#ff0000", "#00ff00", "#0000ff", "#ffff00");
var LOCATIONS  = newArray("Lower Right", "Lower Left", "Upper Right", "Upper Left");
var ACTIONS    = newArray("Continue to export",
                          "Auto min/max from random sets",
                          "Preview the selected set (tune with Brightness/Contrast)");
var AVG_MODES  = newArray("Median (robust to empty wells)", "Mean");
var TIFF_EXTS  = newArray(".tif", ".tiff");        // opened directly; anything else via Bio-Formats
var UM         = "um";      // replaced by the micro sign at start (keeps this file pure ASCII)

// ------------------------------------------------------------- shared state
// file scan
var gFiles = newArray(256);
var gN     = 0;
// grouping (set s, channel c  ->  gSetPaths[s * gNCh + c], "" when missing)
var gNCh           = 0;
var gSets          = 0;
var gSetRel        = newArray(1);   // subfolder relative to source, "" or "A01\"
var gSetBase       = newArray(1);   // file name without channel text / extension
var gSetPaths      = newArray(1);
var gSetCount      = newArray(1);   // number of channels present
var gComplete      = 0;
var gFirstComplete = -1;
var gChCount       = newArray(7);
var gUnmatched     = 0;
var gUnmatchedEx   = "";
var gDup           = 0;
var gDupEx         = "";
var gAmbig         = 0;
var gMatchPos      = -1;
// composite building
var gErr         = "";
var gWarn        = "";
var gSlots       = 0;
var gSlotCh      = newArray(8);     // composite channel (1-based) -> channel index
var gRefBitDepth = 16;
var gRefCal      = "";
// annotations
var gBar       = false;
var gBarLen    = 50;
var gBarThick  = 6;
var gBarFont   = 24;
var gBarColor  = "White";
var gBarLoc    = "Lower Right";
var gLabel     = false;
var gLabelSize = 24;
var gLabelHex  = "#ffffff";
var gLabelText = "";

main();

// ============================================================================
//  MAIN
// ============================================================================
function main() {
    UM = fromCharCode(181) + "m";

    // ===== STEP 1 - folders ================================================
    Dialog.create("Composite Batch - 1/4  Folders");
    Dialog.addDirectory("Source folder", pget("src", ""));
    Dialog.addCheckbox("Include subfolders (e.g. plate\\A01, plate\\A02 ...)", pgetB("recursive", true));
    Dialog.addString("File extensions", pget("exts", ".C01"), 20);
    Dialog.addDirectory("Destination folder", pget("dst", ""));
    Dialog.addNumber("Number of channels", pgetN("nch", 2), 0, 3, "(1 to 7)");
    Dialog.show();
    src       = normDir(Dialog.getString());
    exts      = Dialog.getString();
    dst       = normDir(Dialog.getString());
    recursive = Dialog.getCheckbox();
    nCh       = round(Dialog.getNumber());

    if (!File.isDirectory(src)) exit("Source folder not found:\n" + src);
    if (dst == "") exit("Please choose a destination folder.");
    if (nCh < 1 || nCh > 7) exit("Number of channels must be between 1 and 7.");
    makeDirs(dst);
    if (!File.isDirectory(dst)) exit("Could not create the destination folder:\n" + dst);
    pset("src", src); pset("dst", dst); pset("exts", exts);
    pset("recursive", recursive); pset("nch", nCh);

    // ---- scan + list ------------------------------------------------------
    skipLower = "";                                   // don't read our own outputs
    if (toLowerCase(dst) != toLowerCase(src)) skipLower = toLowerCase(dst);
    gN = 0;
    showStatus("Scanning " + src + " ...");
    scanDir(src, recursive, parseExts(exts), skipLower);
    if (gN == 0) exit("No file with extension(s) '" + exts + "' found in:\n" + src);
    files = Array.trim(gFiles, gN);
    Array.sort(files);

    print("\\Clear");
    print("=== Composite Batch - source files (" + gN + ") ===");
    print("Source: " + src);
    for (i = 0; i < gN; i++) print("   " + substring(files[i], lengthOf(src)));

    // ===== STEP 2 - channel rules + grouping check =========================
    tags = newArray(nCh);
    for (c = 0; c < nCh; c++) tags[c] = pget("tag" + c, DEF_TAGS[c]);
    caseSens = pgetB("case", false);
    incMode  = pget("incomplete", INCOMPLETE[0]);

    goBack = true;
    while (goBack) {
        Dialog.create("Composite Batch - 2/4  Channel rules");
        Dialog.addMessage(gN + " files found (full list in the Log window). First names:\n" + examples(files, src, 6));
        Dialog.addMessage("A file belongs to a channel when its NAME contains the channel text.\n" +
                          "Files in the same folder whose names are identical once that text\n" +
                          "is removed form one set (= one composite).");
        for (c = 0; c < nCh; c++) Dialog.addString("Channel " + (c + 1) + " text", tags[c], 14);
        Dialog.addCheckbox("Case-sensitive matching", caseSens);
        Dialog.show();
        allFilled = true;
        for (c = 0; c < nCh; c++) {
            tags[c] = Dialog.getString();
            if (tags[c] == "") allFilled = false;
        }
        caseSens = Dialog.getCheckbox();
        if (!allFilled) { showMessage("Composite Batch", "Every channel needs a text."); continue; }
        if (hasDuplicates(tags)) { showMessage("Composite Batch", "Two channels have the same text."); continue; }

        groupSets(files, src, tags, caseSens);
        if (gSets == 0) {
            showMessage("Composite Batch", "No file name contains any of the channel texts.\n" +
                        "Compare them with the names listed in the Log window.");
            continue;
        }

        Dialog.create("Composite Batch - 2/4  Grouping check");
        Dialog.addMessage(groupingSummary(tags));
        Dialog.addChoice("Incomplete sets", INCOMPLETE, incMode);
        Dialog.addCheckbox("Print the full grouping table to the Log (tab-separated, Excel-ready)", false);
        Dialog.addCheckbox("Go back and edit the channel texts", false);
        Dialog.show();
        incMode    = Dialog.getChoice();
        printTable = Dialog.getCheckbox();
        goBack     = Dialog.getCheckbox();
        if (printTable) printGrouping(tags);
    }
    skipIncomplete = (incMode == INCOMPLETE[0]);
    if (skipIncomplete && gComplete == 0)
        exit("No complete set (all " + nCh + " channels present) was found.\n" +
             "Check the channel texts, or choose 'Export with the channels present'.");
    for (c = 0; c < nCh; c++) pset("tag" + c, tags[c]);
    pset("case", caseSens); pset("incomplete", incMode);

    print("");
    print("=== Grouping ===");
    print(groupingSummary(tags));

    // ===== STEP 3 - colours + display ranges (with preview) =================
    luts = newArray(nCh); mins = newArray(nCh); maxs = newArray(nCh);
    for (c = 0; c < nCh; c++) luts[c] = pget("lut." + tagKey(tags[c]), LUTS[c]);
    initRanges(tags, mins, maxs);
    dec = 0;
    if (gRefBitDepth == 32) dec = 3;

    nPrev = minOf(gSets, 500);                        // keep the drop-down usable
    prevNames = newArray(nPrev);
    for (s = 0; s < nPrev; s++) prevNames[s] = displayName(s);
    cur = 0;
    if (gFirstComplete >= 0 && gFirstComplete < nPrev) cur = gFirstComplete;

    nRand   = pgetN("autoN", 20);
    seed    = pgetN("autoSeed", 1);
    avgMode = pget("autoAvg", AVG_MODES[0]);
    defAction = ACTIONS[1];                           // first visit: suggest the auto range
    done = false;
    while (!done) {
        Dialog.create("Composite Batch - 3/4  Colours and display ranges");
        Dialog.addMessage("One colour and one FIXED min/max per channel, applied to every set,\n" +
                          "so intensities stay comparable between images.");
        for (c = 0; c < nCh; c++) {
            Dialog.addChoice(tags[c], LUTS, luts[c]);
            Dialog.addToSameRow(); Dialog.addNumber("min", mins[c], dec, 8, "");
            Dialog.addToSameRow(); Dialog.addNumber("max", maxs[c], dec, 8, "");
        }
        Dialog.addMessage("Auto: each image gets an auto-contrast (0.35 % saturated pixels),\n" +
                          "then the min and max are averaged over randomly picked sets.");
        Dialog.addNumber("Random sets", nRand, 0, 4, "");
        Dialog.addToSameRow(); Dialog.addChoice("average", AVG_MODES, avgMode);
        Dialog.addToSameRow(); Dialog.addNumber("seed", seed, 0, 4, "");
        Dialog.addMessage("Preview: opens one set with these settings; tune it with Brightness/Contrast,\n" +
                          "the values come back here when you click OK.");
        Dialog.addChoice("Set to preview", prevNames, prevNames[cur]);
        Dialog.addRadioButtonGroup("When I click OK:", ACTIONS, ACTIONS.length, 1, defAction);
        Dialog.show();
        for (c = 0; c < nCh; c++) luts[c] = Dialog.getChoice();
        avgMode = Dialog.getChoice();
        sel     = Dialog.getChoice();
        for (c = 0; c < nCh; c++) {
            mins[c] = Dialog.getNumber();
            maxs[c] = Dialog.getNumber();
            if (maxs[c] <= mins[c]) maxs[c] = mins[c] + 1;
        }
        nRand  = maxOf(1, round(Dialog.getNumber()));
        seed   = round(Dialog.getNumber());
        action = Dialog.getRadioButton();
        cur    = indexOfItem(prevNames, sel);
        if (action == ACTIONS[0]) {
            done = true;
        } else if (action == ACTIONS[1]) {
            autoRanges(nRand, (avgMode == AVG_MODES[0]), seed, mins, maxs);
            defAction = ACTIONS[2];                   // next: suggest checking a preview
        } else {
            previewSet(cur, luts, mins, maxs);
            defAction = ACTIONS[0];                   // next: suggest continuing
        }
    }
    pset("autoN", nRand); pset("autoSeed", seed); pset("autoAvg", avgMode);
    for (c = 0; c < nCh; c++) {
        pset("lut." + tagKey(tags[c]), luts[c]);
        pset("range." + tagKey(tags[c]), "" + mins[c] + "," + maxs[c]);
    }

    // ===== STEP 4 - export settings =========================================
    nToDo = gSets;
    if (skipIncomplete) nToDo = gComplete;
    Dialog.create("Composite Batch - 4/4  Export");
    Dialog.addMessage(nToDo + " composite(s) will be written to:\n" + dst);
    Dialog.addChoice("File format", FORMATS, pget("format", FORMATS[0]));
    Dialog.addString("Composite name suffix", pget("suffix", "_composite"), 16);
    Dialog.addCheckbox("Recreate the subfolder structure in the destination", pgetB("keepTree", true));
    Dialog.addCheckbox("Overwrite existing files", pgetB("overwrite", false));
    Dialog.addCheckbox("Also export each channel alone, in its colour", pgetB("singles", false));
    Dialog.addMessage("Scale bar  -  calibration found in the files: " + gRefCal);
    Dialog.addCheckbox("Add scale bar", pgetB("bar", false));
    Dialog.addNumber("Pixel size", pgetN("px", 0), 4, 8, UM + "/pixel  (0 = use the files' calibration)");
    Dialog.addNumber("Bar length", pgetN("barLen", 50), 0, 8, UM);
    Dialog.addNumber("Bar thickness", pgetN("barThick", 6), 0, 8, "pixels");
    Dialog.addNumber("Bar text size", pgetN("barFont", 24), 0, 8, "pixels  (0 = no text)");
    Dialog.addChoice("Bar colour", COLORS, pget("barColor", "White"));
    Dialog.addChoice("Bar position", LOCATIONS, pget("barLoc", "Lower Right"));
    Dialog.addMessage("Label");
    Dialog.addCheckbox("Burn in the set name (top left)", pgetB("label", false));
    Dialog.addNumber("Label size", pgetN("labelSize", 24), 0, 8, "pixels");
    Dialog.addChoice("Label colour", COLORS, pget("labelColor", "White"));
    Dialog.addMessage("JPEG quality follows Edit > Options > Input/Output (default 85).");
    Dialog.show();
    fmtChoice  = Dialog.getChoice();
    gBarColor  = Dialog.getChoice();
    gBarLoc    = Dialog.getChoice();
    labelColor = Dialog.getChoice();
    suffix     = Dialog.getString();
    keepTree   = Dialog.getCheckbox();
    overwrite  = Dialog.getCheckbox();
    singles    = Dialog.getCheckbox();
    gBar       = Dialog.getCheckbox();
    gLabel     = Dialog.getCheckbox();
    pxSize     = Dialog.getNumber();
    gBarLen    = Dialog.getNumber();
    gBarThick  = Dialog.getNumber();
    gBarFont   = Dialog.getNumber();
    gLabelSize = Dialog.getNumber();
    gLabelHex  = COLOR_HEX[indexOfItem(COLORS, labelColor)];
    fi  = indexOfItem(FORMATS, fmtChoice);
    ext = FMT_EXT[fi];

    pset("format", fmtChoice); pset("suffix", suffix); pset("keepTree", keepTree);
    pset("overwrite", overwrite); pset("singles", singles); pset("bar", gBar);
    pset("px", d2s(pxSize, 6)); pset("barLen", gBarLen); pset("barThick", gBarThick);
    pset("barFont", gBarFont); pset("barColor", gBarColor); pset("barLoc", gBarLoc);
    pset("label", gLabel); pset("labelSize", gLabelSize); pset("labelColor", labelColor);

    // ===== RUN ==============================================================
    ts = timeStamp();
    print("");
    print("=== Composite Batch run " + ts + "  (ImageJ " + getVersion() + ") ===");
    print("Source        : " + src + "   subfolders: " + yn(recursive) + "   extensions: " + exts);
    print("Destination   : " + dst);
    for (c = 0; c < nCh; c++)
        print("Channel " + (c + 1) + "     : text '" + tags[c] + "'   colour " + luts[c] +
              "   min " + mins[c] + "   max " + maxs[c]);
    print("Case-sensitive: " + yn(caseSens) + "   incomplete sets: " + incMode);
    print("Format        : " + FMT_TYPE[fi] + "   suffix '" + suffix + "'   keep folders: " + yn(keepTree) +
          "   overwrite: " + yn(overwrite) + "   single channels: " + yn(singles));
    if (gBar) print("Scale bar     : " + gBarLen + " " + UM + ", " + gBarThick + " px, text " + gBarFont +
                    " px, " + gBarColor + ", " + gBarLoc + ", pixel size " + pxSize + " (0 = from files)");
    if (gLabel) print("Label         : " + gLabelSize + " px, " + labelColor);
    print("");

    t0 = getTime();
    nDone = 0; nSingle = 0; nSkipInc = 0; nSkipExist = 0; nErr = 0; nUncal = 0;
    gWarn = "";
    setBatchMode(true);
    for (s = 0; s < gSets; s++) {
        showProgress(s + 1, gSets);
        showStatus("Composite " + (s + 1) + " / " + gSets);
        if (gSetCount[s] < nCh && skipIncomplete) {
            nSkipInc++;
            print("SKIP  incomplete     " + displayName(s));
            continue;
        }
        outDir = dst;
        if (keepTree) outDir = dst + gSetRel[s];
        base = outBaseName(s, keepTree);
        outPath = outDir + base + suffix + ext;
        if (File.exists(outPath) && !overwrite) {
            nSkipExist++;
            print("SKIP  exists         " + outPath);
            continue;
        }
        makeDirs(outDir);

        comp = buildComposite(s, luts, mins, maxs, pxSize);
        if (comp == 0) {
            nErr++;
            print("ERROR " + displayName(s) + " : " + gErr);
            continue;
        }
        getPixelSize(unit, pw, ph);
        if (gBar && isUncalibrated(unit)) nUncal++;
        gLabelText = labelFor(s);

        rgb = renderRGB(comp);
        saveAs(FMT_TYPE[fi], outPath);
        closeID(rgb);
        nDone++;
        print("OK    " + outPath);

        if (singles) {
            for (j = 1; j <= gSlots; j++) {
                c = gSlotCh[j];
                sPath = outDir + base + "_" + cleanName(tags[c]) + ext;
                if (File.exists(sPath) && !overwrite) {
                    nSkipExist++;
                    print("SKIP  exists         " + sPath);
                    continue;
                }
                selectImage(comp);
                if (gSlots > 1) run("Duplicate...", "title=cb_single duplicate channels=" + j);
                else            run("Duplicate...", "title=cb_single");
                sid = getImageID();
                run(luts[c]);
                setMinAndMax(mins[c], maxs[c]);
                rgb = renderRGB(sid);
                saveAs(FMT_TYPE[fi], sPath);
                closeID(rgb);
                closeID(sid);
                nSingle++;
                print("OK    " + sPath);
            }
        }
        closeID(comp);
    }
    setBatchMode(false);
    showProgress(1);
    secs = (getTime() - t0) / 1000;

    // ---- summary + log ----------------------------------------------------
    msg = "Composites written: " + nDone + "\n";
    if (singles)        msg += "Single-channel images written: " + nSingle + "\n";
    if (nSkipInc > 0)   msg += "Skipped, incomplete: " + nSkipInc + "\n";
    if (nSkipExist > 0) msg += "Skipped, file already exists: " + nSkipExist + "\n";
    if (nErr > 0)       msg += "Errors: " + nErr + "  (see log)\n";
    if (nUncal > 0)     msg += "Warning: " + nUncal + " set(s) had no pixel calibration, scale bar drawn in pixels.\n" +
                               "   -> enter the pixel size in the Export dialog.\n";
    if (gWarn != "")    msg += "Note: " + gWarn + "\n";
    msg += "Time: " + d2s(secs, 1) + " s";
    print("");
    print("=== Summary ===");
    print(msg);
    logPath = dst + "CompositeBatch_log_" + ts + ".txt";
    File.saveString(getInfo("log"), logPath);
    showMessage("Composite Batch - done", msg + "\n\nLog saved:\n" + logPath);
}

// ============================================================================
//  FILE SCAN
// ============================================================================
function scanDir(dir, recursive, extList, skipLower) {
    list = getFileList(dir);
    for (i = 0; i < list.length; i++) {
        name = list[i];
        if (startsWith(name, ".")) continue;
        if (endsWith(name, "/")) {                      // sub-folder
            if (!recursive) continue;
            sub = dir + substring(name, 0, lengthOf(name) - 1) + File.separator;
            if (skipLower != "" && startsWith(toLowerCase(sub), skipLower)) continue;
            scanDir(sub, recursive, extList, skipLower);
        } else if (hasExt(name, extList)) {
            addFile(dir + name);
        }
    }
}

function addFile(p) {
    if (gN >= gFiles.length) gFiles = Array.concat(gFiles, newArray(gFiles.length));
    gFiles[gN] = p;
    gN++;
}

function parseExts(s) {
    parts = split(s, ",; ");
    out = newArray(parts.length);
    n = 0;
    for (i = 0; i < parts.length; i++) {
        e = toLowerCase(parts[i]);
        if (e == "") continue;
        if (!startsWith(e, ".")) e = "." + e;
        out[n] = e;
        n++;
    }
    return Array.trim(out, n);
}

function hasExt(name, extList) {
    lower = toLowerCase(name);
    for (k = 0; k < extList.length; k++) if (endsWith(lower, extList[k])) return true;
    return false;
}

// ============================================================================
//  GROUPING
// ============================================================================
// Returns the channel index whose text matches 'base' (or -1) and sets gMatchPos.
// Several matches: the one ending nearest the end of the name wins, then the longest.
function matchChannel(base, tags, caseSens) {
    s = base;
    if (!caseSens) s = toLowerCase(base);
    best = -1; bestEnd = -1; bestLen = 0; hits = 0;
    gMatchPos = -1;
    for (c = 0; c < tags.length; c++) {
        t = tags[c];
        if (!caseSens) t = toLowerCase(t);
        pos = lastIndexOf(s, t);
        if (pos < 0) continue;
        hits++;
        e = pos + lengthOf(t);
        if (e > bestEnd || (e == bestEnd && lengthOf(t) > bestLen)) {
            best = c; bestEnd = e; bestLen = lengthOf(t); gMatchPos = pos;
        }
    }
    if (hits > 1) gAmbig++;
    return best;
}

function groupSets(files, src, tags, caseSens) {
    nCh = tags.length;
    gNCh = nCh;
    gUnmatched = 0; gUnmatchedEx = ""; gAmbig = 0; gDup = 0; gDupEx = "";
    gChCount = newArray(nCh);
    entries = newArray(files.length);
    nE = 0;
    for (i = 0; i < files.length; i++) {
        p = files[i];
        name = File.getName(p);
        rel = substring(p, lengthOf(src), lengthOf(p) - lengthOf(name));
        dot = lastIndexOf(name, ".");
        base = name;
        if (dot > 0) base = substring(name, 0, dot);
        c = matchChannel(base, tags, caseSens);
        if (c < 0) {
            gUnmatched++;
            if (gUnmatched <= 3) gUnmatchedEx += "\n      " + rel + name;
            continue;
        }
        key = substring(base, 0, gMatchPos) + substring(base, gMatchPos + lengthOf(tags[c]));
        gChCount[c]++;
        entries[nE] = rel + "\t" + key + "\t" + c + "\t" + p;   // tab never occurs in paths
        nE++;
    }
    gSets = 0; gComplete = 0; gFirstComplete = -1;
    if (nE == 0) return;
    entries = Array.trim(entries, nE);
    Array.sort(entries);                                       // same set -> adjacent

    gSetRel   = newArray(nE);
    gSetBase  = newArray(nE);
    gSetCount = newArray(nE);
    gSetPaths = newArray(nE * nCh);
    for (i = 0; i < gSetPaths.length; i++) gSetPaths[i] = "";

    lastKey = "";
    for (i = 0; i < nE; i++) {
        e  = entries[i];
        t1 = indexOf(e, "\t");
        t2 = indexOf(e, "\t", t1 + 1);
        t3 = indexOf(e, "\t", t2 + 1);
        groupKey = substring(e, 0, t2);
        if (gSets == 0 || groupKey != lastKey) {
            gSetRel[gSets]   = substring(e, 0, t1);
            gSetBase[gSets]  = substring(e, t1 + 1, t2);
            gSetCount[gSets] = 0;
            gSets++;
            lastKey = groupKey;
        }
        s   = gSets - 1;
        c   = parseInt(substring(e, t2 + 1, t3));
        p   = substring(e, t3 + 1);
        idx = s * nCh + c;
        if (gSetPaths[idx] != "") {
            gDup++;
            if (gDup <= 3) gDupEx += "\n      " + substring(p, lengthOf(src));
            continue;
        }
        gSetPaths[idx] = p;
        gSetCount[s]++;
    }
    for (s = 0; s < gSets; s++) {
        if (gSetCount[s] == nCh) {
            gComplete++;
            if (gFirstComplete < 0) gFirstComplete = s;
        }
    }
}

function groupingSummary(tags) {
    nCh = tags.length;
    m = "Files matched per channel:\n";
    for (c = 0; c < nCh; c++) m += "      " + tags[c] + " : " + gChCount[c] + "\n";
    m += "Files matching no channel (ignored): " + gUnmatched + gUnmatchedEx + "\n";
    if (gDup > 0)   m += "Duplicates (same set and channel, extra file ignored): " + gDup + gDupEx + "\n";
    if (gAmbig > 0) m += "Names containing several channel texts: " + gAmbig + "  (text nearest the end wins)\n";
    m += "\nSets: " + gSets + "    complete: " + gComplete + "    incomplete: " + (gSets - gComplete) + "\n";
    ex = gFirstComplete;
    if (ex < 0) ex = 0;
    m += "\nExample set: " + displayName(ex) + "\n";
    for (c = 0; c < nCh; c++) {
        p = gSetPaths[ex * nCh + c];
        f = "(missing)";
        if (p != "") f = File.getName(p);
        m += "      " + tags[c] + "  ->  " + f + "\n";
    }
    return m;
}

function printGrouping(tags) {
    nCh = tags.length;
    print("");
    print("=== Grouping table ===");
    h = "Set\tFolder\tName\tChannels";
    for (c = 0; c < nCh; c++) h += "\t" + tags[c];
    print(h);
    for (s = 0; s < gSets; s++) {
        row = "" + (s + 1) + "\t" + gSetRel[s] + "\t" + gSetBase[s] + "\t" + gSetCount[s] + "/" + nCh;
        for (c = 0; c < nCh; c++) {
            p = gSetPaths[s * nCh + c];
            if (p == "") row += "\t-";
            else         row += "\t" + File.getName(p);
        }
        print(row);
    }
}

function displayName(s) {
    n = gSetRel[s] + cleanName(gSetBase[s]);
    if (n == "") n = "set " + (s + 1);
    if (gSetCount[s] < gNCh) n += "   [incomplete " + gSetCount[s] + "/" + gNCh + "]";
    return n;
}

// ============================================================================
//  DISPLAY RANGES + PREVIEW
// ============================================================================
// Start values: last range used for this channel text, else auto-contrast
// (0.35 % saturated) of the first image found for that channel.
function initRanges(tags, mins, maxs) {
    setBatchMode(true);
    gRefCal = "";
    for (c = 0; c < tags.length; c++) {
        lo = 0; hi = 255;
        p = firstPathForChannel(c);
        if (p != "") {
            openImage(p);
            if (gRefCal == "") {
                gRefBitDepth = bitDepth();
                getPixelSize(unit, pw, ph);
                if (isUncalibrated(unit)) gRefCal = "none (images not calibrated)";
                else gRefCal = d2s(pw, 4) + " " + unit + " per pixel";
            }
            run("Enhance Contrast", "saturated=0.35");
            getMinAndMax(lo, hi);
            close();
        }
        mins[c] = lo; maxs[c] = hi;
        r = pget("range." + tagKey(tags[c]), "");
        if (r != "") {
            parts = split(r, ",");
            if (parts.length == 2) {
                a = parseFloat(parts[0]); b = parseFloat(parts[1]);
                if (!isNaN(a) && !isNaN(b) && b > a) { mins[c] = a; maxs[c] = b; }
            }
        }
    }
    setBatchMode(false);
    if (gRefCal == "") gRefCal = "unknown";
}

// Auto range from random sets: auto-contrast (0.35 % saturated) on each image,
// then median or mean of the per-image min and max. Complete sets are sampled
// first. The seed makes the draw reproducible; sampled sets go to the Log.
function autoRanges(nSample, useMedian, seed, mins, maxs) {
    cand = newArray(gSets);
    n = 0;
    for (s = 0; s < gSets; s++) if (gSetCount[s] == gNCh) { cand[n] = s; n++; }
    if (n == 0) { for (s = 0; s < gSets; s++) cand[s] = s; n = gSets; }
    cand = Array.trim(cand, n);
    random("seed", seed);
    for (k = n - 1; k > 0; k--) {                     // Fisher-Yates shuffle
        r = floor(random * (k + 1));
        t = cand[k]; cand[k] = cand[r]; cand[r] = t;
    }
    n = minOf(nSample, n);

    lows  = newArray(n * gNCh);
    highs = newArray(n * gNCh);
    Array.fill(lows, NaN); Array.fill(highs, NaN);
    print("");
    print("=== Auto range: " + n + " random sets (seed " + seed + ") ===");
    setBatchMode(true);
    for (k = 0; k < n; k++) {
        s = cand[k];
        showProgress(k + 1, n);
        showStatus("Auto range: set " + (k + 1) + " / " + n);
        print("   " + displayName(s));
        for (c = 0; c < gNCh; c++) {
            p = gSetPaths[s * gNCh + c];
            if (p == "") continue;
            openImage(p);
            if (nSlices > 1) setSlice(1);
            run("Enhance Contrast", "saturated=0.35");
            getMinAndMax(lo, hi);
            close();
            lows[k * gNCh + c] = lo;
            highs[k * gNCh + c] = hi;
        }
    }
    setBatchMode(false);
    showProgress(1);
    for (c = 0; c < gNCh; c++) {
        lo = channelStat(lows, c, n, useMedian);
        hi = channelStat(highs, c, n, useMedian);
        if (!isNaN(lo) && !isNaN(hi) && hi > lo) { mins[c] = lo; maxs[c] = hi; }
        print("   channel " + (c + 1) + ": min " + mins[c] + "   max " + maxs[c]);
    }
}

// Median or mean of channel c's values in a flat [set * gNCh + channel] array.
function channelStat(flat, c, n, useMedian) {
    v = newArray(n);
    m = 0;
    for (k = 0; k < n; k++) {
        x = flat[k * gNCh + c];
        if (!isNaN(x)) { v[m] = x; m++; }
    }
    if (m == 0) return NaN;
    v = Array.trim(v, m);
    if (!useMedian) { Array.getStatistics(v, vmin, vmax, vmean); return vmean; }
    Array.sort(v);
    if (m % 2 == 1) return v[(m - 1) / 2];
    return (v[m / 2 - 1] + v[m / 2]) / 2;
}

// Opens a file: TIFF directly, anything else (e.g. Cellomics .C01) with Bio-Formats.
function openImage(p) {
    if (hasExt(p, TIFF_EXTS)) open(p);
    else run("Bio-Formats Importer", "open=[" + p + "] color_mode=Default view=Hyperstack stack_order=XYCZT");
}

function firstPathForChannel(c) {
    if (gFirstComplete >= 0) return gSetPaths[gFirstComplete * gNCh + c];
    for (s = 0; s < gSets; s++) {
        p = gSetPaths[s * gNCh + c];
        if (p != "") return p;
    }
    return "";
}

// Opens set s as a visible composite, lets the user tune it, reads min/max back.
function previewSet(s, luts, mins, maxs) {
    setBatchMode(true);
    comp = buildComposite(s, luts, mins, maxs, 0);
    if (comp == 0) {
        setBatchMode(false);
        showMessage("Composite Batch - preview", "This set cannot be opened:\n" + gErr);
        return;
    }
    rename("PREVIEW - " + displayName(s));
    setBatchMode("exit and display");
    run("Brightness/Contrast...");
    waitForUser("Composite Batch - preview",
        "Tune each channel in the Brightness/Contrast window:\n" +
        "   - pick a channel with the 'c' slider under the image\n" +
        "   - drag Minimum / Maximum, or click 'Set' to type values\n" +
        "   - do NOT click 'Apply' (not needed, it would change the pixels)\n \n" +
        "Click OK here when done: each channel's min/max is read back.");
    if (!isOpen(comp)) {
        showMessage("Composite Batch - preview", "The preview window was closed: values unchanged.");
        return;
    }
    selectImage(comp);
    for (j = 1; j <= gSlots; j++) {
        if (gSlots > 1) Stack.setChannel(j);
        getMinAndMax(lo, hi);
        mins[gSlotCh[j]] = lo;
        maxs[gSlotCh[j]] = hi;
    }
    close();
}

// ============================================================================
//  COMPOSITE + RENDERING
// ============================================================================
// Opens the images of set s and returns the ID of a composite (or of the single
// image when only one channel is present), with LUTs and ranges applied.
// Returns 0 on error (message in gErr). Opened images are closed on error.
function buildComposite(s, luts, mins, maxs, pxSize) {
    gErr = ""; gSlots = 0;
    opened = newArray(gNCh);
    w = -1; h = -1; bd = -1;
    mergeArgs = "";
    for (c = 0; c < gNCh; c++) {
        p = gSetPaths[s * gNCh + c];
        if (p == "") continue;
        openImage(p);
        id = getImageID();
        if (nSlices > 1) {                              // keep the first plane only
            setSlice(1);
            run("Duplicate...", "title=cb_plane");
            plane = getImageID();
            closeID(id);
            selectImage(plane);
            id = plane;
            gWarn = "some files were stacks; only their first plane was used.";
        }
        if (bitDepth() == 24) {
            closeID(id); closeAll(opened, gSlots);
            gErr = "RGB file, a grayscale image is expected: " + File.getName(p);
            return 0;
        }
        if (w < 0) { w = getWidth(); h = getHeight(); bd = bitDepth(); }
        else if (getWidth() != w || getHeight() != h || bitDepth() != bd) {
            closeID(id); closeAll(opened, gSlots);
            gErr = "size or bit depth differs from the other channels: " + File.getName(p);
            return 0;
        }
        gSlots++;
        rename("cb_slot" + gSlots);
        opened[gSlots - 1] = id;
        gSlotCh[gSlots] = c;
        mergeArgs += "c" + gSlots + "=[cb_slot" + gSlots + "] ";
    }
    if (gSlots == 0) { gErr = "no image in this set."; return 0; }

    if (gSlots == 1) {
        comp = opened[0];
        selectImage(comp);
        run(luts[gSlotCh[1]]);
        setMinAndMax(mins[gSlotCh[1]], maxs[gSlotCh[1]]);
    } else {
        run("Merge Channels...", mergeArgs + "create");
        comp = getImageID();
        for (j = 1; j <= gSlots; j++) {
            Stack.setChannel(j);
            run(luts[gSlotCh[j]]);
            setMinAndMax(mins[gSlotCh[j]], maxs[gSlotCh[j]]);
        }
        Stack.setChannel(1);
        Stack.setDisplayMode("composite");
    }
    if (pxSize > 0) setVoxelSize(pxSize, pxSize, 1, "micron");
    return comp;
}

// Returns the ID of a new RGB image = what you see, plus scale bar / label.
// The source image is left untouched.
function renderRGB(srcID) {
    selectImage(srcID);
    run("Duplicate...", "title=cb_render duplicate");
    tmp = getImageID();
    addAnnotations();
    if (Overlay.size > 0) {
        run("Flatten");
        out = getImageID();
        closeID(tmp);
    } else {
        run("RGB Color");                               // in place or new window
        out = getImageID();
        if (out != tmp) closeID(tmp);
    }
    selectImage(out);
    return out;
}

function addAnnotations() {
    if (gBar) {
        opt = "width=" + gBarLen + " height=" + gBarThick + " thickness=" + gBarThick;
        if (gBarFont > 0) opt += " font=" + gBarFont;
        else              opt += " font=12 hide";
        opt += " color=[" + gBarColor + "] background=None location=[" + gBarLoc + "] horizontal bold overlay";
        run("Scale Bar...", opt);
    }
    if (gLabel && gLabelText != "") {
        setFont("SansSerif", gLabelSize, "bold antialiased");
        m = round(gLabelSize / 2);
        y = m;
        if (gBar && gBarLoc == "Upper Left") y = getHeight() - m - round(gLabelSize * 1.4);
        makeText(gLabelText, m, y);
        Overlay.addSelection(gLabelHex);
        run("Select None");
    }
}

// ============================================================================
//  NAMES + PATHS
// ============================================================================
function outBaseName(s, keepTree) {
    rel = gSetRel[s];
    b = gSetBase[s];
    if (!keepTree && rel != "") b = replace(rel, "[\\\\/]", "_") + b;   // avoid name clashes
    b = cleanName(b);
    if (b == "" && rel != "") b = cleanName(replace(rel, "[\\\\/]", "_"));
    if (b == "") b = "set_" + IJ.pad(s + 1, 4);
    return b;
}

function labelFor(s) {
    rel = gSetRel[s];
    b = cleanName(gSetBase[s]);
    if (rel != "") {
        folder = replace(substring(rel, 0, lengthOf(rel) - 1), "[\\\\/]", " / ");
        if (b == "") return folder;
        return folder + "  " + b;
    }
    return b;
}

// Collapses repeated separators left by removing the channel text, trims the ends.
function cleanName(s) {
    s = replace(s, "_{2,}", "_");
    s = replace(s, "-{2,}", "-");
    s = replace(s, " {2,}", " ");
    s = replace(s, "^[-_. ]+", "");
    s = replace(s, "[-_. ]+$", "");
    return s;
}

function normDir(d) {
    if (d == "") return d;
    if (!endsWith(d, "/") && !endsWith(d, "\\")) d = d + File.separator;
    return d;
}

function makeDirs(dir) {
    if (File.isDirectory(dir)) return;
    parent = File.getParent(dir);
    if (parent != "" && !File.isDirectory(parent)) makeDirs(parent + File.separator);
    File.makeDirectory(dir);
}

function examples(files, src, k) {
    s = "";
    n = minOf(k, files.length);
    for (i = 0; i < n; i++) s += "      " + substring(files[i], lengthOf(src)) + "\n";
    if (files.length > n) s += "      ...";
    return s;
}

// ============================================================================
//  SMALL HELPERS
// ============================================================================
function closeID(id) {
    if (id != 0 && isOpen(id)) { selectImage(id); close(); }
}

function closeAll(ids, n) {
    for (k = 0; k < n; k++) closeID(ids[k]);
}

function isUncalibrated(unit) {
    u = toLowerCase(unit);
    return (u == "pixel" || u == "pixels" || u == "");
}

function hasDuplicates(arr) {
    for (a = 0; a < arr.length; a++)
        for (b = a + 1; b < arr.length; b++)
            if (toLowerCase(arr[a]) == toLowerCase(arr[b])) return true;
    return false;
}

function indexOfItem(arr, v) {
    for (k = 0; k < arr.length; k++) if (arr[k] == v) return k;
    return 0;
}

function tagKey(t) { return toLowerCase(replace(t, "[^A-Za-z0-9]", "_")); }

function yn(b) { if (b) return "yes"; return "no"; }

function timeStamp() {
    getDateAndTime(yr, mo, dw, dm, hr, mi, se, ms);
    return "" + yr + IJ.pad(mo + 1, 2) + IJ.pad(dm, 2) + "-" + IJ.pad(hr, 2) + IJ.pad(mi, 2) + IJ.pad(se, 2);
}

// Settings remembered between runs (stored in Fiji's IJ_Prefs.txt).
function pget(k, d)  { return call("ij.Prefs.get", PREF + k, "" + d); }
function pgetN(k, d) { v = parseFloat(pget(k, d)); if (isNaN(v)) return d; return v; }
function pgetB(k, d) { dv = "0"; if (d) dv = "1"; return (pget(k, dv) == "1"); }
function pset(k, v)  { call("ij.Prefs.set", PREF + k, "" + v); }
