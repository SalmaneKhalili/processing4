package processing.app;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.Assumptions;
import java.io.File;
import java.io.FileOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.stream.Stream;
import java.util.zip.ZipEntry;
import java.util.zip.ZipOutputStream;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertTrue;

public class UtilTest {

    @Test
    public void unzipLeaksFileDescriptorsOnException() throws IOException {
        // thi only runs on Linux where /proc/self/fd exists otherwise skip
        Assumptions.assumeTrue(new File("/proc/self/fd").exists(),
                "Skipping test: /proc/self/fd not available (not Linux)");
        // create a temporary zip file here with one entry
        File zipFile = File.createTempFile("leak-test", ".zip");
        zipFile.deleteOnExit();
        File destDir = File.createTempFile("dest", "");
        destDir.delete();        // turn into a directory
        destDir.mkdirs();
        destDir.deleteOnExit();
        // build a simple zip file
        try (ZipOutputStream zos = new ZipOutputStream(new FileOutputStream(zipFile))) {
            ZipEntry entry = new ZipEntry("test.txt");
            zos.putNextEntry(entry);
            zos.write("hello".getBytes());
            zos.closeEntry();
        }
        // make the destination directory read‑only – this will cause extraction to fail
        destDir.setReadOnly();
        boolean exceptionThrown = false;
        try {
            Util.unzip(zipFile, destDir);
        } catch (IOException e) {
            exceptionThrown = true;
        }
        assertTrue(exceptionThrown, "Expected an exception because destDir is read‑only");

        // check if the file is open by examining /proc/self/fd symlinks
        boolean fileStillOpen = isFileOpen(zipFile);
        assertFalse(fileStillOpen, "File " + zipFile + " is still open after exception – leak detected");

        destDir.setWritable(true);
        destDir.delete();
        zipFile.delete();
    }

    /**
     * Checks whether the given file is currently open by the current process.
     * Works on Linux by reading the symlinks in /proc/self/fd.
     */
    private boolean isFileOpen(File file) throws IOException {
        Path fdDir = Paths.get("/proc/self/fd");
        String targetPath = file.getCanonicalPath();

        try (Stream<Path> fdPaths = Files.list(fdDir)) {
            return fdPaths
                    .map(Path::toFile)
                    .map(File::toPath)
                    .map(path -> {
                        try {
                            return Files.readSymbolicLink(path);
                        } catch (IOException e) {
                            return null; // not a symlink or inaccessible
                        }
                    })
                    .filter(resolved -> resolved != null)
                    .anyMatch(resolved -> resolved.toString().equals(targetPath));
        }
    }
}