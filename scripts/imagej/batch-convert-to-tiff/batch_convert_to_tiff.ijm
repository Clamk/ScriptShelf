// ---
// title: Batch convert a folder of images to TIFF
// tags: batch, files, conversion
// tested:
// notes: Asks for an input and an output folder, opens every file in the input
//   folder and saves it as .tif in the output folder. Subfolders are skipped.
//   Runs in batch mode, so no windows pop up.
// ---
// Batch-convert every image in a folder to TIFF
input = getDirectory("Choose input folder");
output = getDirectory("Choose output folder");
list = getFileList(input);
setBatchMode(true);
for (i = 0; i < list.length; i++) {
    if (endsWith(list[i], "/")) continue; // skip subfolders
    open(input + list[i]);
    saveAs("Tiff", output + File.nameWithoutExtension + ".tif");
    close();
}
setBatchMode(false);
print("Done: " + list.length + " items processed");
