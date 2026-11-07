// Overlay_Viewer.ijm
// Browse nucleus images and lay their segmentation outlines on top.
//
// Dataset layout: pick the plate folder. Files are collected from the folders
// inside it too (plate\A01, plate\A02, ...), so one folder per well works.
//
// Setup: the macro lists the first 10 files it finds. You pick one nucleus image
// and its outline file. From that pair it learns the naming pattern (for example
// "outline name = image name + o") and the two file extensions, then applies the
// same pattern to every image.
//
// Cellomics .C01 outline files are decoded by a small Python reader (Fiji's Jython)
// because Bio-Formats rejects them. If one cannot be read, the reason is shown in the
// dialog and in the Log window.
//
// Outlines are images (for example exported from HCS Studio): black = background,
// every outline line has its own grey level. Any non-zero pixel is an outline.
// The macro recolours them with one colour and makes the black part transparent.
//
// Controls (one dialog, re-shown after every OK):
//   Folder and image number, LUT, display min/max (shared by all images),
//   outline colour, outline opacity (0 = hidden), outline thickness.
// Export: tick "Export ALL images" and press OK. You are asked for a destination
//   folder, then every image is saved with the current settings, outlines burned in.
//   Files are named <folder>_<image>_overlay.<ext> in one flat folder.

requires("1.53k");

// ---------- settings kept between dialog rounds ----------
var viewTitle = "Overlay viewer";
var lutNames = newArray("Grays", "Green", "Red", "Blue", "Cyan", "Magenta", "Yellow", "Fire", "Ice", "Green Fire Blue", "Spectrum");
var colorNames = newArray("yellow", "red", "green", "cyan", "magenta", "blue", "orange", "white");
var colorR = newArray(255, 255, 0, 0, 255, 0, 255, 255);
var colorG = newArray(255, 0, 255, 255, 0, 0, 165, 255);
var colorB = newArray(0, 0, 0, 255, 255, 255, 0, 255);
var files = newArray(0);        // image paths relative to dir, "/" separated
var pairSeg = newArray(0);      // outline path for each image, "" when none
var imgKeys = newArray(0);      // distinct image folders, with first and last+1 file index
var imgFrom = newArray(0);
var imgTo = newArray(0);
var gKeys = newArray(0);
var gFrom = newArray(0);
var gTo = newArray(0);
var walkOut = newArray(0);
var dir = "";
var segExt = "";
var ruleDrop = 0;               // characters removed from the end of the image name
var ruleAdd = "";               // text added in their place
var pairSummary = "";
var dispMin = -1;
var dispMax = -1;
var cur = 0;
var lutIdx = 0;
var colIdx = 0;
var opacity = 100;
var lineW = 1;
var flipOutline = false;
var outlineError = "";
var status = "";
var segDrawn = false;
var winX = -1;
var winY = -1;
var zoomLevel = 0;

// ---------- 1. choose dataset and learn the pairing pattern ----------
dir = getDirectory("Choose the plate folder (or the folder with the images)");

showStatus("Looking for files...");
walkOut = newArray(0);
walk(dir, "");
Array.sort(walkOut);
if (walkOut.length < 2) exit("Need at least two files (an image and its outline) in\n" + dir);
allFiles = Array.copy(walkOut);

examples = Array.slice(allFiles, 0, minOf(10, allFiles.length));
Dialog.create("Dataset setup");
Dialog.addMessage("Found " + allFiles.length + " files. The first " + examples.length + " are listed.\nPick one nucleus image and its outline file (same folder).\nThe naming pattern is learned from this pair.");
Dialog.addChoice("Nucleus image", examples, examples[0]);
Dialog.addChoice("Its outline file", examples, examples[1]);
Dialog.show();
ex1 = Dialog.getChoice();
ex2 = Dialog.getChoice();

if (ex1 == ex2) exit("Pick two different files: the image and its outline.");
fold1 = folderOf(ex1);
fold2 = folderOf(ex2);
if (fold1 != fold2) exit("The image and its outline must be in the same folder.");

n1 = nameOf(ex1);
n2 = nameOf(ex2);
imgExt = extOf(n1);
segExt = extOf(n2);
if (imgExt == "" || segExt == "") exit("Both files need an extension (for example .tif).");
ib = stripExt(n1);
sb = stripExt(n2);
cp = commonPrefix(ib, sb);
if (cp == 0) exit("The two names have nothing in common at the start:\n" + n1 + "\n" + n2 + "\nPick the image and the outline of the same field.");
ruleDrop = lengthOf(ib) - cp;
ruleAdd = substring(sb, cp);
check = expectedOutline(ex1);
if (check != ex2) exit("Could not reproduce the outline name from the image name.\nPlease pick a different pair.");

// images: every file with the image extension (when both extensions are equal,
// files that are the outline of another file are left out)
sameExt = (toLowerCase(imgExt) == toLowerCase(segExt));
cand = newArray(0);
for (i = 0; i < allFiles.length; i++) {
    if (endsWith(toLowerCase(allFiles[i]), "." + toLowerCase(imgExt))) cand = Array.concat(cand, allFiles[i]);
}
outlineSet = "|";
if (sameExt) {
    for (i = 0; i < cand.length; i++) {
        e = expectedOutline(cand[i]);
        if (e != "" && e != cand[i] && File.exists(dir + e)) outlineSet = outlineSet + toLowerCase(e) + "|";
    }
}
for (i = 0; i < cand.length; i++) {
    if (sameExt) {
        if (indexOf(outlineSet, "|" + toLowerCase(cand[i]) + "|") >= 0) continue;
        // a name the rule leaves unchanged already is an outline name (rules like d0 -> o1)
        selfName = expectedOutline(cand[i]);
        if (toLowerCase(selfName) == toLowerCase(cand[i])) continue;
    }
    files = Array.concat(files, cand[i]);
}
if (files.length == 0) exit("No *." + imgExt + " images found in\n" + dir);
Array.sort(files);

groupIndex(files);
imgKeys = Array.copy(gKeys);
imgFrom = Array.copy(gFrom);
imgTo = Array.copy(gTo);

folderLabels = newArray(imgKeys.length);
for (i = 0; i < imgKeys.length; i++) {
    folderLabels[i] = "(top folder)";
    if (imgKeys[i] != "") folderLabels[i] = substring(imgKeys[i], 0, lengthOf(imgKeys[i]) - 1);
}

// pair every image with its outline using the learned pattern
pairSeg = newArray(files.length);
matched = 0;
missing = newArray(0);
for (i = 0; i < files.length; i++) {
    showProgress(i, files.length);
    e = expectedOutline(files[i]);
    if (e != "" && File.exists(dir + e)) {
        pairSeg[i] = e;
        matched++;
    } else {
        missing = Array.concat(missing, files[i]);
    }
}
showProgress(1);

ruleText = "outline name = image name";
if (ruleDrop > 0) ruleText = ruleText + " without its last " + ruleDrop + " character(s)";
ruleText = ruleText + ", plus \"" + ruleAdd + "\", extension ." + segExt;
pairSummary = "Outlines found for " + matched + " of " + files.length + " images";
print("Pairing rule: " + ruleText);
print(pairSummary);
for (i = 0; i < minOf(missing.length, 20); i++) print("  no outline: " + missing[i]);
if (missing.length > 20) print("  ... and " + (missing.length - 20) + " more");

pairSummary = pairSummary + " (" + imgKeys.length + " folder(s))";

// ---------- 2. viewer loop ----------
render(false);

while (true) {
    curG = groupOf(cur);
    Dialog.create("Overlay viewer");
    Dialog.addMessage(status);
    Dialog.addChoice("Folder (well)", folderLabels, folderLabels[curG]);
    Dialog.addNumber("Image number in that folder (1 to " + (imgTo[curG] - imgFrom[curG]) + ")", cur - imgFrom[curG] + 1);
    Dialog.addCheckbox("Go to the next image instead (continues into the next folder)", false);
    Dialog.addChoice("LUT", lutNames, lutNames[lutIdx]);
    Dialog.addSlider("Display min (all images)", 0, 65535, dispMin);
    Dialog.addSlider("Display max (all images)", 0, 65535, dispMax);
    Dialog.addCheckbox("Auto-contrast on this image, then use for all", false);
    Dialog.addCheckbox("Show histogram of this image", false);
    Dialog.addChoice("Outline colour", colorNames, colorNames[colIdx]);
    Dialog.addSlider("Outline opacity % (0 = transparent)", 0, 100, opacity);
    Dialog.addNumber("Outline thickness (px)", lineW);
    Dialog.addChoice("Export format", newArray("PNG", "TIFF", "JPEG"), "PNG");
    Dialog.addCheckbox("Flip outline vertically (only if outlines look mirrored)", flipOutline);
    Dialog.addCheckbox("Export ALL images with these settings (asks for a destination)", false);
    Dialog.addCheckbox("Quit after this update", false);
    Dialog.show();   // Cancel stops the macro and leaves the viewer open

    folderChoice = Dialog.getChoice();
    imgNum = Dialog.getNumber();
    dispMin = Dialog.getNumber();
    dispMax = Dialog.getNumber();
    opacity = Dialog.getNumber();
    lineW = Dialog.getNumber();
    goNext = Dialog.getCheckbox();
    lutIdx = indexOfName(lutNames, Dialog.getChoice());
    autoFlag = Dialog.getCheckbox();
    showHist = Dialog.getCheckbox();
    flipOutline = Dialog.getCheckbox();
    colIdx = indexOfName(colorNames, Dialog.getChoice());
    expFmt = Dialog.getChoice();
    exportFlag = Dialog.getCheckbox();
    quitFlag = Dialog.getCheckbox();

    if (goNext) {
        cur = (cur + 1) % files.length;
    } else {
        g = indexOfName(folderLabels, folderChoice);
        k = round(imgNum);
        k = maxOf(1, minOf(k, imgTo[g] - imgFrom[g]));
        cur = imgFrom[g] + k - 1;
    }
    if (dispMax <= dispMin) dispMax = dispMin + 1;
    lineW = maxOf(1, round(lineW));

    render(autoFlag);
    if (exportFlag) exportAll(expFmt);

    if (showHist) {
        run("Histogram");
        selectImage(viewTitle);
    }
    if (quitFlag) break;
}
print("Overlay viewer finished. Last image: " + files[cur]);

// ---------- functions ----------

// Collect every file under base+rel into walkOut (relative paths, "/" separated).
function walk(base, rel) {
    list = getFileList(base + rel);
    for (w = 0; w < list.length; w++) {
        nm = list[w];
        low = toLowerCase(nm);
        if (endsWith(nm, "/")) {
            walk(base, rel + nm);
        } else if (!startsWith(nm, ".") && low != "thumbs.db" && low != "desktop.ini") {
            walkOut = Array.concat(walkOut, rel + nm);
        }
    }
}

// The outline path an image should have under the learned pattern ("" if the name is too short).
function expectedOutline(p) {
    b = stripExt(nameOf(p));
    keep = lengthOf(b) - ruleDrop;
    if (keep < 1) return "";
    fo = folderOf(p);
    result = fo + substring(b, 0, keep) + ruleAdd + "." + segExt;
    return result;
}

// "A01/img.tif" -> "A01/"   and   "img.tif" -> ""
function folderOf(p) {
    s = lastIndexOf(p, "/");
    if (s < 0) return "";
    return substring(p, 0, s + 1);
}

// "A01/img.tif" -> "img.tif"
function nameOf(p) {
    s = lastIndexOf(p, "/");
    if (s < 0) return p;
    return substring(p, s + 1);
}

// "img.tif" -> "tif"   (empty when there is no extension)
function extOf(s) {
    dot = lastIndexOf(s, ".");
    if (dot < 0) return "";
    return substring(s, dot + 1);
}

// Number of leading characters two names have in common.
function commonPrefix(a, b) {
    n = minOf(lengthOf(a), lengthOf(b));
    for (k = 0; k < n; k++) {
        if (substring(a, k, k + 1) != substring(b, k, k + 1)) return k;
    }
    return n;
}

// Distinct folders of a sorted path list, with first and last+1 index (into gKeys, gFrom, gTo).
function groupIndex(arr) {
    gKeys = newArray(0);
    gFrom = newArray(0);
    gTo = newArray(0);
    for (q = 0; q < arr.length; q++) {
        f = folderOf(arr[q]);
        n = gKeys.length;
        isNew = (n == 0);
        if (n > 0) isNew = (f != gKeys[n - 1]);
        if (isNew) {
            gKeys = Array.concat(gKeys, f);
            gFrom = Array.concat(gFrom, q);
            gTo = Array.concat(gTo, q + 1);
        } else {
            gTo[n - 1] = q + 1;
        }
    }
}

// Index of the image folder that contains image number idx.
function groupOf(idx) {
    for (q = 0; q < imgKeys.length; q++) {
        if (idx >= imgFrom[q] && idx < imgTo[q]) return q;
    }
    return 0;
}

// Update the viewer window (keeps its position and zoom).
function render(autoContrast) {
    setBatchMode(true);

    if (isOpen("Histogram of " + viewTitle)) {
        selectImage("Histogram of " + viewTitle);
        close();
    }
    if (isOpen(viewTitle)) {
        selectImage(viewTitle);
        getLocationAndSize(winX, winY, ww, wh);
        zoomLevel = getZoom();
        close();
    }

    id = build(cur, viewTitle, autoContrast);
    selectImage(id);
    iw = getWidth();
    ih = getHeight();
    setBatchMode("exit and display");
    if (zoomLevel > 0) run("Set... ", "zoom=" + (zoomLevel * 100) + " x=" + (iw / 2) + " y=" + (ih / 2));
    if (winX >= 0) setLocation(winX, winY);
}

// Open image number idx, apply LUT, display range and outline overlay. Returns the image ID.
// Expects batch mode to be on. Sets the global status text.
function build(idx, title, autoContrast) {
    name = files[idx];
    if (!openAny(dir + name)) {
        setBatchMode(false);
        exit("Could not open " + name + "\nBio-Formats does not recognise this file.");
    }
    rename(title);
    viewID = getImageID();
    iw = getWidth();
    ih = getHeight();
    if (nSlices > 1) setSlice(1);

    run(lutNames[lutIdx]);
    if (autoContrast || dispMin < 0) {
        run("Enhance Contrast", "saturated=0.35");
        getMinAndMax(dispMin, dispMax);
    } else {
        setMinAndMax(dispMin, dispMax);
    }

    segDrawn = false;
    g = groupOf(idx);
    status = pairSummary + "\nImage " + (idx + 1) + " of " + files.length + " (" + (idx - imgFrom[g] + 1) + " of " + (imgTo[g] - imgFrom[g]) + " in its folder)\n" + name;

    if (pairSeg[idx] == "") {
        status = status + "\nOutline: none found";
    } else if (opacity > 0) {
        segPath = dir + pairSeg[idx];
        beforeSeg = nImages;
        openOutline(segPath);
        if (nImages == beforeSeg) {
            status = status + "\nOutline: could not read " + nameOf(pairSeg[idx]) + "\n" + outlineError;
        } else {
            segID = getImageID();
            if (getWidth() != iw || getHeight() != ih) {
                status = status + "\nOutline: " + nameOf(pairSeg[idx]) + " has a different size than the image";
            } else if (makeOutlineRGB("outline_tmp")) {
                selectImage(viewID);
                run("Add Image...", "image=outline_tmp x=0 y=0 opacity=" + opacity + " zero");
                segDrawn = true;
                status = status + "\nOutline: " + nameOf(pairSeg[idx]);
            } else {
                status = status + "\nOutline: " + nameOf(pairSeg[idx]) + " is empty (all black)";
            }
            selectImage(segID);
            close();
        }
    } else {
        status = status + "\nOutline: " + nameOf(pairSeg[idx]) + " (hidden, opacity 0)";
    }

    selectImage(viewID);
    return viewID;
}

// Turn the active outline image into an RGB picture: chosen colour where the
// pixel is not zero, black (= transparent in the overlay) everywhere else.
// Returns false when the image has no non-zero pixel.
function makeOutlineRGB(newTitle) {
    if (nSlices > 1) setSlice(1);
    if (bitDepth() == 24) run("8-bit");
    getStatistics(area, mean, mn, mx);
    if (mx <= 0) return false;

    run("32-bit");
    run("Macro...", "code=v=(v>0)*255");
    setMinAndMax(0, 255);
    run("8-bit");
    run("Grays");
    if (lineW > 1) run("Maximum...", "radius=" + (lineW - 1));

    r = newArray(256);
    g = newArray(256);
    b = newArray(256);
    for (k = 0; k < 256; k++) {
        r[k] = k * colorR[colIdx] / 255;
        g[k] = k * colorG[colIdx] / 255;
        b[k] = k * colorB[colIdx] / 255;
    }
    setLut(r, g, b);
    run("RGB Color");
    rename(newTitle);
    return true;
}

// Save every image with the current LUT, display range, outline colour, opacity and thickness.
// Output is an RGB picture with the outline burned in: <folder>_<image name>_overlay.<ext>
function exportAll(fmtName) {
    ext = ".png";
    saveFmt = "PNG";
    if (fmtName == "TIFF") { ext = ".tif"; saveFmt = "Tiff"; }
    if (fmtName == "JPEG") { ext = ".jpg"; saveFmt = "Jpeg"; }

    out = getDirectory("Choose the destination folder for the exported overlays");

    existing = 0;
    for (n = 0; n < files.length; n++) {
        if (File.exists(out + outName(files[n]) + "_overlay" + ext)) existing++;
    }
    if (existing > 0) {
        if (!getBoolean(existing + " file(s) in this folder will be overwritten.\nContinue?")) return;
    }

    keepStatus = status;
    saved = 0;
    noSeg = 0;
    setBatchMode(true);
    for (n = 0; n < files.length; n++) {
        showStatus("Exporting overlay " + (n + 1) + " of " + files.length);
        showProgress(n, files.length);
        id = build(n, "export_tmp", false);
        if (opacity > 0 && !segDrawn) noSeg++;
        run("Flatten");
        saveAs(saveFmt, out + outName(files[n]) + "_overlay" + ext);
        close();
        selectImage(id);
        close();
        saved++;
    }
    showProgress(1);
    setBatchMode(false);

    msg = "Exported " + saved + " image(s) to\n" + out;
    if (noSeg > 0) msg = msg + "\n" + noSeg + " of them without an outline (none found, unreadable or empty)";
    status = msg + "\n---\n" + keepStatus;
}

// "A01/img.tif" -> "A01_img"  (folder names joined with the file name, no extension)
function outName(p) {
    noExt = stripExt(p);
    flat = replace(noExt, "/", "_");
    return flat;
}

// Open an outline file. Cellomics .C01 outline files are read by a small Python reader
// (Fiji's Jython), because Bio-Formats rejects them. Anything else goes through openAny().
// A reading problem never stops the macro: the reason is left in outlineError.
// Nothing is returned: the caller checks whether a new image appeared (nImages).
function openOutline(path) {
    outlineError = "";
    if (toLowerCase(segExt) != "c01") {
        opened = openAny(path);
        return;
    }
    call("ij.Prefs.set", "ovl.status", "");
    flipPy = "False";
    if (flipOutline) flipPy = "True";
    py = "";
    //PY-BEGIN
    py = py + "import struct, zlib\n";
    py = py + "from java.lang import String\n";
    py = py + "from java.nio import ByteBuffer, ByteOrder\n";
    py = py + "from ij import ImagePlus, IJ, Prefs\n";
    py = py + "from ij.process import ByteProcessor, ShortProcessor\n";
    py = py + "import jarray\n";
    py = py + "TAB1 = [bytearray([(v >> (7 - k)) & 1 for k in range(8)]) for v in range(256)]\n";
    py = py + "TAB4 = [bytearray([v >> 4, v & 15]) for v in range(256)]\n";
    py = py + "def decode(raw):\n";
    py = py + "    d = bytearray(zlib.decompress(bytes(raw[4:])))\n";
    py = py + "    x, y = struct.unpack('<ii', bytes(d[4:12]))\n";
    py = py + "    npl, nb = struct.unpack('<hh', bytes(d[12:16]))\n";
    py = py + "    info = 'x=%d y=%d planes=%d bits=%d size=%d' % (x, y, npl, nb, len(d))\n";
    py = py + "    if x <= 0 or y <= 0 or x > 30000 or y > 30000:\n";
    py = py + "        return None, info + ' (image size not plausible)'\n";
    py = py + "    if nb == 1:\n";
    py = py + "        rb = ((x + 31) // 32) * 4\n";
    py = py + "    elif nb == 4:\n";
    py = py + "        rb = ((x * 4 + 31) // 32) * 4\n";
    py = py + "    elif nb == 8:\n";
    py = py + "        rb = ((x + 3) // 4) * 4\n";
    py = py + "    elif nb == 16:\n";
    py = py + "        rb = ((x * 2 + 3) // 4) * 4\n";
    py = py + "    else:\n";
    py = py + "        return None, info + ' (bits per pixel not supported)'\n";
    py = py + "    need = rb * y\n";
    py = py + "    if len(d) < 52 + need:\n";
    py = py + "        return None, info + ' (pixel data shorter than the header says)'\n";
    py = py + "    start = 52\n";
    py = py + "    if npl <= 1 and len(d) != 52 + need:\n";
    py = py + "        start = len(d) - need\n";
    py = py + "    body = d[start:start + need]\n";
    py = py + "    out = bytearray()\n";
    py = py + "    for r in range(y):\n";
    py = py + "        line = body[r * rb:(r + 1) * rb]\n";
    py = py + "        if nb == 8:\n";
    py = py + "            out += line[:x]\n";
    py = py + "        elif nb == 16:\n";
    py = py + "            out += line[:x * 2]\n";
    py = py + "        else:\n";
    py = py + "            row = bytearray()\n";
    py = py + "            tab = TAB1\n";
    py = py + "            if nb == 4:\n";
    py = py + "                tab = TAB4\n";
    py = py + "            for c in line:\n";
    py = py + "                row += tab[c]\n";
    py = py + "            out += row[:x]\n";
    py = py + "    bits = 8\n";
    py = py + "    if nb == 16:\n";
    py = py + "        bits = 16\n";
    py = py + "    return (x, y, bits, out), info\n";
    //PY-END
    py = py + "path = '" + replace(path, "\\", "/") + "'\n";
    py = py + "flip = " + flipPy + "\n";
    py = py + "imp = None\n";
    py = py + "try:\n";
    py = py + "    f = open(path, 'rb')\n";
    py = py + "    raw = f.read()\n";
    py = py + "    f.close()\n";
    py = py + "    res, info = decode(raw)\n";
    py = py + "    if res is not None:\n";
    py = py + "        x, y, bits, out = res\n";
    py = py + "        jb = String(str(out)).getBytes('ISO-8859-1')\n";
    py = py + "        if bits == 16:\n";
    py = py + "            sh = jarray.zeros(x * y, 'h')\n";
    py = py + "            ByteBuffer.wrap(jb).order(ByteOrder.LITTLE_ENDIAN).asShortBuffer().get(sh)\n";
    py = py + "            ip = ShortProcessor(x, y, sh, None)\n";
    py = py + "        else:\n";
    py = py + "            ip = ByteProcessor(x, y, jb, None)\n";
    py = py + "        if flip:\n";
    py = py + "            ip.flipVertical()\n";
    py = py + "        imp = ImagePlus('outline_raw', ip)\n";
    py = py + "except Exception as e:\n";
    py = py + "    info = 'error: ' + str(e)\n";
    py = py + "Prefs.set('ovl.status', info)\n";
    py = py + "if imp is None:\n";
    py = py + "    IJ.log('Outline reader: ' + info + '  file: ' + path)\n";
    py = py + "else:\n";
    py = py + "    imp.show()\n";
    eval("python", py);
    outlineError = call("ij.Prefs.get", "ovl.status", "");
}

// Open any file through Bio-Formats when it recognises it, else plain ImageJ for common formats.
function openAny(path) {
    before = nImages;
    run("Bio-Formats Macro Extensions");
    Ext.isThisType(path, recognised);
    if (recognised == "true") {
        run("Bio-Formats Importer", "open=[" + path + "] color_mode=Default view=Hyperstack stack_order=XYCZT");
    } else {
        low = toLowerCase(path);
        if (endsWith(low, ".tif") || endsWith(low, ".tiff") || endsWith(low, ".png") || endsWith(low, ".bmp") || endsWith(low, ".jpg")) open(path);
    }
    return nImages > before;
}

function stripExt(s) {
    dot = lastIndexOf(s, ".");
    if (dot > lastIndexOf(s, "/") + 0 && dot > 0) return substring(s, 0, dot);
    return s;
}

function indexOfName(arr, s) {
    for (k = 0; k < arr.length; k++) {
        if (arr[k] == s) return k;
    }
    return 0;
}
