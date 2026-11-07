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