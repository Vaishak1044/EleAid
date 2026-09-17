# FFmpeg release input

The lightweight Windows installer includes `ffmpeg.exe` and `ffprobe.exe`, but
they are intentionally excluded from Git history: each binary is larger than
GitHub's normal per-file limit and must retain its distributor's license notice.

Before building a local installer, download a prebuilt Windows FFmpeg package
from a trusted source linked by the official FFmpeg download page. Place these
two files beside this README:

```text
release_models/tools/ffmpeg/ffmpeg.exe
release_models/tools/ffmpeg/ffprobe.exe
```

Keep the matching license/notice files with the final GitHub Release asset.
Do not commit the binaries to the source repository. The release builder checks
for the two files and stops with a clear error if they are absent.
