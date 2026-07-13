# Showcase assets

These images are real iPhone 17 Pro Max Simulator captures from the debug build.
The home, result, and receipt states use the app's debug-only `--aic-showcase`
launch arguments so the portfolio tour is reproducible without a live account,
location permission, or private credentials. Release builds do not compile the
showcase fixture.

The App Store-ready 1320 x 2868 PNG captures live in
`distribution/app-store/screenshots/en-US/`. `local-scan.jpg` is an exact JPEG
render of the current home capture. The older optional sign-in capture is kept
only as a historical artifact and is not used in the current product tour.

The landscape `social-preview.png` is a non-distorted crop of that same home
capture, sized at 1280 x 640 for GitHub's repository social preview. Upload it
in **Settings → General → Social preview** after changes to the image have
been reviewed.
