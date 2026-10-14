# SplitUp - In-App OTA Update Guide 🚀

This document provides a step-by-step checklist for releasing Over-The-Air (OTA) in-app updates for SplitUp whenever you fix bugs or add new features.

With this setup, **users do not need to visit the website, redownload, or reinstall the app**. Their installed app will detect the update in their **Profile** tab, download it in the background, and perform an in-place upgrade while preserving all offline data, SQLite ledgers, and login sessions.

---

## 📋 Overview of the Update Flow

```
1. Code Changes (Bug fixes / New features)
        ↓
2. Bump Version & Build Number in `app/pubspec.yaml`
        ↓
3. Compile Release APK (`--split-per-abi`)
        ↓
4. Copy APK to `website/downloads/`
        ↓
5. Update Version Metadata in `index.js` & `routes.ts`
        ↓
6. Git Commit & Push (`git push origin main`)
        ↓
7. Users see the "Update" badge in Profile and update with 1 tap!
```

---

## Step-by-Step Release Checklist

### Step 1: Bump Version & Build Number in Flutter

Open [`app/pubspec.yaml`](file:///c:/Users/Nasir%20Sada/Desktop/splitup/app/pubspec.yaml) and locate the `version:` line:

```yaml
# Format: <version_name>+<build_number>
version: 1.0.3+4
```

- **`version_name`** (e.g., `1.0.3`): What is shown to users as the display version.
- **`build_number`** (e.g., `4`): An incrementing integer. **The app uses this number to decide if an update is available.** It must be greater than the previous build number (e.g., `3` $\to$ `4`).

---

### Step 2: Build the Production APK

Open PowerShell or your terminal in the project root and run:

```powershell
cd app
flutter build apk --release --split-per-abi --android-skip-build-dependency-validation
```

> [!TIP]
> **Why `--split-per-abi`?**
> This ensures modern ARM 64-bit phones download only the necessary architecture, keeping the APK ultra-light (**~20 MB** instead of 500+ MB).

The built APK will be located at:
`app/build/app/outputs/flutter-apk/app-arm64-v8a-release.apk`

---

### Step 3: Copy APK to the Website Downloads Directory

From the project root, copy the new binary to the website downloads folder:

```powershell
# From project root:
Copy-Item app\build\app\outputs\flutter-apk\app-arm64-v8a-release.apk website\downloads\splitup-v1.0.2.apk -Force
```

*(Optional: If you want to rename the file to reflect the new version such as `splitup-v1.0.3.apk`, also update the filename and links accordingly in `index.js` and `website/index.html`).*

Check that the file size is ~20 MB:
```powershell
Get-Item website\downloads\splitup-v1.0.2.apk | Select-Object Name, @{Name="SizeMB";Expression={[math]::Round($_.Length / 1MB, 2)}}
```

---

### Step 4: Update Version Metadata on the Backend

Update the metadata so the app knows a new version exists.

#### 1. In [`index.js`](file:///c:/Users/Nasir%20Sada/Desktop/splitup/index.js) (Root Vercel Serverless Handler)
Update the `/app/version` endpoint block:

```javascript
// 4. Version check endpoints
app.get(['/version', '/app/version'], (req, res) => {
  res.json({
    latest_version: '1.0.3',     // Display version
    currentVersion: '1.0.3',
    build_number: 4,             // Incremented build number (CRITICAL)
    buildNumber: 4,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.2.apk',
    downloadUrl: '/downloads/splitup-v1.0.2.apk',
    file_size_mb: 20.74,         // APK size in MB
    release_notes: 'SplitUp v1.0.3: Fixed [bug description] and improved [feature].',
  });
});
```

#### 2. In [`backend/src/modules/appVersion/routes.ts`](file:///c:/Users/Nasir%20Sada/Desktop/splitup/backend/src/modules/appVersion/routes.ts)
Update the matching values:

```typescript
appVersionRouter.get('/app/version', (req, res) => {
  res.json({
    latest_version: '1.0.3',
    currentVersion: '1.0.3',
    build_number: 4,
    buildNumber: 4,
    min_supported_build: 1,
    minSupportedVersion: '1.0.0',
    download_url: 'https://split-up-two.vercel.app/downloads/splitup-v1.0.2.apk',
    downloadUrl: '/downloads/splitup-v1.0.2.apk',
    file_size_mb: 20.74,
    release_notes: 'SplitUp v1.0.3: Fixed [bug description] and improved [feature].',
  });
});
```

Then rebuild the backend TypeScript:
```powershell
cd backend
npm run build
cd ..
```

---

### Step 5: Deploy to Vercel via Git

Commit the changes and push to `main`:

```powershell
git add app/pubspec.yaml website/downloads/ index.js backend/src/modules/appVersion/routes.ts backend/dist/
git commit -m "release: v1.0.3 (build 4) - [brief description of changes]"
git push origin main
```

Vercel will automatically build and deploy within ~15 seconds.

---

### Step 6: (Optional) Update GitHub Release Asset

To keep your GitHub Releases page synchronized with the website:

```powershell
gh release upload v1.0.2 website\downloads\splitup-v1.0.2.apk --clobber
```

---

## 📱 How Users Experience the Update

1. **Automatic Detection:**
   When users open SplitUp, the app checks `https://split-up-two.vercel.app/app/version` in the background.

2. **Visual Notification:**
   In their **Profile** tab, the `App Version` tile dynamically displays an emerald badge:
   `Update (v1.0.3) ⇡`

3. **Bottom Sheet & Download:**
   Tapping the tile opens the update modal showing:
   - Version number & file size (e.g. `20.7 MB`).
   - "WHAT'S NEW" release notes.
   - **Download & Install Update** button.

4. **In-Place Installation:**
   - Real-time progress bar (`Downloading update (45%)...`).
   - Android's native package installer immediately appears asking "Do you want to update this app?".
   - Upon confirming, the update installs in seconds without losing:
     - SQLite expense ledgers
     - Offline queue
     - User session / login tokens

---

## ⚠️ Important Rules for Smooth Updates

1. **Keystore Consistency:**
   Never change the signing keystore or package name (`com.splitup.app`). Android requires updates to be signed with the same key to allow in-place replacement without uninstalling.
2. **Build Number Must Increase:**
   Always increase the integer build number (`3` $\to$ `4` $\to$ `5`). If the server returns a build number equal to or lower than what is installed on the phone, the app will consider itself up to date.
3. **Verify Link Before Pushing:**
   Ensure the `download_url` in `index.js` returns HTTP 200 and points directly to the APK file.
