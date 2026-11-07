// =====================================================================
// Overlay_Viewer_v2.ijm
// Browse microscopy images with their segmentation outlines on top.
//
// WORKFLOW
//   1. You pick ONE image and ONE matching outline file (just as examples).
//   2. The macro works out how the two file names differ (their "endings"),
//      scans the plate folder (incl. well subfolders) and builds two lists:
//      all images, all outlines.
//   3. Images are sorted by file name. Each image is matched to its outline
//      BY NAME (well folder + name without ending). Images with no outline
//      (empty wells) are shown without overlay, or skipped if you tick
//      "Only show images that have an outline".
//   4. A control window lets you set display min/max and LUT ONCE; the
//      same settings are applied to every image while you browse.
//
// CONTROL WINDOW NOTES
//   - Click OK to apply settings. The window then re-opens with the same
//     values, so you can keep adjusting. Cancel = quit (images stay open).
//   - "After OK" = Go to next lets you step through by clicking OK repeatedly.
//   - Export writes every overlay as an RGB PNG (display settings burned in).
//
// ASSUMPTIONS
//   - 2D single-channel images (first plane only for stacks).
//   - Outline images: black (0) = background, any other grey = outline.
//   - Outline image has the same width/height as the microscopy image.
// =====================================================================

requires("1.53k");

var imgList = "";
var outList = "";
var imgTail = "";
var outTail = "";
var imgPaths = newArray(0);
var outPaths = newArray(0);
var viewID = 0;
var dispMin = 0;
var dispMax = 255;
var lutName = "Grays";
var outColour = "Red";
var showOutline = true;
var dimWarned = false;

// ---------- 1. Pick example files and detect the name endings ----------
imgPick = File.openDialog("Choose ONE microscopy image (example)");
outPick = File.openDialog("Choose the matching OUTLINE file for that image");
imgName = File.getName(imgPick);
outName = File.getName(outPick);

k = 0;
nMin = minOf(lengthOf(imgName), lengthOf(outName));
while (k < nMin && substring(imgName, k, k + 1) == substring(outName, k, k + 1)) k++;
imgTail = substring(imgName, k);
outTail = substring(outName, k);

plateDir = File.getParent(File.getParent(imgPick));

Dialog.create("Overlay Viewer - setup");
Dialog.addMessage("Check what the macro detected (edit if wrong):");
Dialog.addString("Folder to scan", plateDir, 50);
Dialog.addString("Image names end with", imgTail, 20);
Dialog.addString("Outline names end with", outTail, 20);
Dialog.addCheckbox("Only show images that have an outline (skip empty wells)", false);
Dialog.show();
root = Dialog.getString();
imgTail = Dialog.getString();
outTail = Dialog.getString();
onlyWithOutline = Dialog.getCheckbox();

if (lengthOf(imgTail) == 0 || lengthOf(outTail) == 0)
    exit("Image and outline names need a non-empty ending to tell them apart.");
if (!endsWith(root, "\\") && !endsWith(root, "/")) root = root + File.separator;

// ---------- 2. Scan, sort, pair ----------
showStatus("Scanning folders...");
scan(root);
imgPaths = sortedPaths(imgList, imgTail);
n = imgPaths.length;
if (n == 0) exit("No images found. Check the folder and the image name ending.");

// Pair by NAME (well folder + file name without ending), not by position.
// Images without an outline (e.g. empty wells) simply get an empty path.
outItems = split(outList, "\n");
List.clear();
for (i = 0; i < outItems.length; i++) List.set(pairKey(outItems[i], outTail), outItems[i]);

paired = newArray(n);
nMatched = 0;
for (i = 0; i < n; i++) {
    paired[i] = List.get(pairKey(imgPaths[i], imgTail));
    if (paired[i] != "") nMatched++;
}
outPaths = paired;
nOrphans = outItems.length - nMatched;

if (nMatched == 0)
    exit("No image has a matching outline (" + outItems.length + " outlines found). Check the name endings.");

// Optionally keep only images that have an outline.
if (onlyWithOutline) {
    keepImg = newArray(nMatched);
    keepOut = newArray(nMatched);
    j = 0;
    for (i = 0; i < n; i++) {
        if (outPaths[i] != "") {
            keepImg[j] = imgPaths[i];
            keepOut[j] = outPaths[i];
            j++;
        }
    }
    imgPaths = keepImg;
    outPaths = keepOut;
    n = nMatched;
}
print("Overlay Viewer: " + n + " images shown, " + nMatched + " with outline, " + nOrphans + " outlines without image.");

// ---------- 3. Initial display settings from the first image ----------
open(imgPaths[0]);
bd = bitDepth();
if (bd == 8 || bd == 24) {
    sMin = 0;
    sMax = 255;
} else if (bd == 16) {
    sMin = 0;
    sMax = 65535;
} else {
    getStatistics(area, mean, sMin, sMax);
}
if (bd != 24) {
    run("Enhance Contrast", "saturated=0.35");
    getMinAndMax(dispMin, dispMax);
}
close();

// ---------- 4. Control loop ----------
idx = 0;
showPair(idx);
lutList = newArray("Grays", "Green", "Red", "Blue", "Cyan", "Magenta", "Yellow", "Fire", "Ice");
colList = newArray("Red", "Green", "Blue", "Yellow", "Cyan", "Magenta", "Grays");
stepList = newArray("Stay on this image", "Go to next", "Go to previous");
stepChoice = stepList[0];

while (true) {
    Dialog.create("Overlay Viewer");
    outLabel = "(none - no segmentation for this image)";
    if (outPaths[idx] != "") outLabel = File.getName(outPaths[idx]);
    Dialog.addMessage("Image " + (idx + 1) + " of " + n + "\n" + File.getName(imgPaths[idx]) + "\nOutline: " + outLabel);
    if (n > 1) Dialog.addSlider("Go to image", 1, n, idx + 1);
    Dialog.addChoice("After OK", stepList, stepChoice);
    Dialog.addSlider("Display min", sMin, sMax, dispMin);
    Dialog.addSlider("Display max", sMin, sMax, dispMax);
    Dialog.addChoice("LUT (image)", lutList, lutName);
    Dialog.addChoice("Outline colour", colList, outColour);
    Dialog.addCheckbox("Show outlines", showOutline);
    Dialog.addCheckbox("Auto-contrast from this image (overrides min/max)", false);
    Dialog.addCheckbox("Export all overlays as PNG (asks for folder)", false);
    Dialog.show();

    newIdx = 0;
    if (n > 1) newIdx = Dialog.getNumber() - 1;
    dispMin = Dialog.getNumber();
    dispMax = Dialog.getNumber();
    stepChoice = Dialog.getChoice();
    lutName = Dialog.getChoice();
    outColour = Dialog.getChoice();
    showOutline = Dialog.getCheckbox();
    doAuto = Dialog.getCheckbox();
    doExport = Dialog.getCheckbox();
    if (dispMax <= dispMin) dispMax = dispMin + 1;

    if (stepChoice == "Go to next") newIdx = (newIdx + 1) % n;
    if (stepChoice == "Go to previous") newIdx = (newIdx + n - 1) % n;
    idx = newIdx;

    showPair(idx);

    if (doAuto && bitDepth() != 24) {
        run("Enhance Contrast", "saturated=0.35");
        getMinAndMax(dispMin, dispMax);
    }
    if (doExport) {
        exportAll();
        showPair(idx);
    }
}

// =====================================================================
// FUNCTIONS
// =====================================================================

// Recursively collect image and outline paths into imgList / outList.
function scan(dir) {
    list = getFileList(dir);
    for (i = 0; i < list.length; i++) {
        p = dir + list[i];
        if (endsWith(list[i], "/")) {
            scan(p);
        } else {
            outFirst = lengthOf(outTail) >= lengthOf(imgTail);
            isOut = endsWith(list[i], outTail);
            isImg = endsWith(list[i], imgTail);
            if (outFirst) {
                if (isOut) outList = outList + p + "\n";
                else if (isImg) imgList = imgList + p + "\n";
            } else {
                if (isImg) imgList = imgList + p + "\n";
                else if (isOut) outList = outList + p + "\n";
            }
        }
    }
}

// Sort paths by name WITHOUT the ending, so "A01_1" sorts before "A01_10"
// for both images and outlines, whatever their endings are.
function sortedPaths(list, tail) {
    items = split(list, "\n");
    keyed = newArray(items.length);
    for (i = 0; i < items.length; i++) {
        keyed[i] = substring(items[i], 0, lengthOf(items[i]) - lengthOf(tail)) + "\t" + items[i];
    }
    Array.sort(keyed);
    for (i = 0; i < keyed.length; i++) {
        keyed[i] = substring(keyed[i], indexOf(keyed[i], "\t") + 1);
    }
    return keyed;
}

// Open pair i in the viewer window with the shared display settings.
function showPair(i) {
    hasLoc = false;
    if (viewID != 0 && isOpen(viewID)) {
        selectImage(viewID);
        getLocationAndSize(wx, wy, ww, wh);
        hasLoc = true;
        close();
    }
    open(imgPaths[i]);
    viewID = getImageID();
    if (hasLoc) setLocation(wx, wy);
    if (bitDepth() != 24) {
        run(lutName);
        setMinAndMax(dispMin, dispMax);
    }
    if (showOutline) addOutline(i);
    selectImage(viewID);
}

// Turn the outline image into a coloured, black-transparent overlay.
function addOutline(i) {
    if (outPaths[i] == "") return;   // empty well: image only
    viewW = getWidth();
    viewH = getHeight();
    open(outPaths[i]);
    rename("OUTLINE_TMP");
    outID = getImageID();
    if ((getWidth() != viewW || getHeight() != viewH) && !dimWarned) {
        print("Warning: outline size differs from image size (" + File.getName(outPaths[i]) + "). Overlay will be misaligned.");
        dimWarned = true;
    }
    getStatistics(area, mean, mn, mx);
    if (mx > 0) {
        setThreshold(1, mx);
        run("Convert to Mask");
        if (is("Inverting LUT")) run("Invert LUT");
        run(outColour);
        run("RGB Color");
        selectImage(viewID);
        run("Add Image...", "image=OUTLINE_TMP x=0 y=0 opacity=100 zero");
    }
    selectImage(outID);
    close();
    selectImage(viewID);
}

// Key used to match an image with its outline: well folder name + file name
// without its ending (so identical names in different wells never clash).
function pairKey(path, tail) {
    nm = File.getName(path);
    stem = substring(nm, 0, lengthOf(nm) - lengthOf(tail));
    return File.getName(File.getParent(path)) + "|" + stem;
}

// Save every overlay (display settings burned in) as RGB PNG.
function exportAll() {
    outDir = getDirectory("Choose export folder");
    n = imgPaths.length;
    for (k = 0; k < n; k++) {
        showStatus("Exporting " + (k + 1) + " / " + n);
        showProgress(k / n);
        showPair(k);
        name = File.getName(imgPaths[k]);
        dot = lastIndexOf(name, ".");
        if (dot > 0) name = substring(name, 0, dot);
        run("Flatten");
        saveAs("PNG", outDir + IJ.pad(k + 1, 4) + "_" + name + "_overlay.png");
        close();
    }
    showProgress(1);
    print("Exported " + n + " overlays to " + outDir);
}
