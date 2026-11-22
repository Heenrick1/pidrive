1. Make a free GitHub account, create a new repo, and upload everything in this folder
   (including the hidden .github folder). Pushing runs the build automatically.
2. Repo > Actions > latest "Build IPA" run > download artifact "PiDrive-ipa" (unzip to get PiDrive.ipa).
   If the build fails, copy the red error text from the log and send it to Claude.
3. On Windows: install Sideloadly (or AltServer), plug in the iPhone, drag in PiDrive.ipa,
   sign in with your Apple ID. On the phone: Settings > General > Device Management > trust your Apple ID.
4. Open PiDrive > Settings tab > enter http://<pi-ip> and your password > Save & connect.
Free Apple ID apps expire after 7 days: re-install (Sideloadly) or let AltStore refresh it.
