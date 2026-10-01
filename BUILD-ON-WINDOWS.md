# Build Nexora Teleport IPA from Windows

You cannot compile an iOS app locally on Windows because Xcode requires macOS.
This project includes a GitHub Actions workflow that builds an unsigned iPhone IPA on a GitHub-hosted Mac.

## Steps

1. Create a GitHub repository.
2. Upload the contents of this folder to the repository root.
   The repository root must contain `NexoraTeleport.xcodeproj`, `NexoraTeleport/`, and `.github/`.
3. Open the repository on GitHub.
4. Open **Actions** -> **Build Nexora Teleport IPA**.
5. Click **Run workflow**.
6. Wait for the build to finish.
7. Open the completed workflow run.
8. Download the artifact **NexoraTeleport-unsigned-IPA**.
9. Extract the downloaded artifact ZIP. It contains `NexoraTeleport-unsigned.ipa`.

The IPA is intentionally unsigned. A Windows sideloading/signing tool can sign it for your own iPhone afterward.
