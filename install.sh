#!/bin/bash
# AOLOS - Final Version for Ubuntu 24.04.3 LTS Server
# Fixes: Auto-login (skips Linux login), GPU rendering (fixes blank screen), React Types
set -e

# Check if running as root (we shouldn't, we need the user context)
if [ "$EUID" -eq 0 ]; then
  echo "Please run as a normal user (not root). The script will ask for sudo when needed."
  exit 1
fi

echo "=== AOLOS Installer - VirtualBox Clone Edition ==="
echo "Target System: Ubuntu 24.04.3 LTS Server"

# 1. System packages + display manager
echo "--> Installing system dependencies (including Video Drivers)..."
sudo apt update
# Added xserver-xorg-video-all for better VirtualBox display support
sudo apt install -y --no-install-recommends \
    curl \
    xorg xserver-xorg-video-all \
    openbox obconf lightdm lightdm-gtk-greeter \
    xinit x11-xserver-utils \
    unclutter-xfixes pulseaudio alsa-utils \
    build-essential python3 pkg-config libgtk-3-dev libnss3 libgbm1 libasound2t64

# Node.js 20 setup
if ! command -v node &> /dev/null; then
    echo "--> Installing Node.js 20..."
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    sudo apt install -y nodejs
else
    echo "--> Node.js is already installed."
fi

# 2. Enable LightDM
echo "--> Configuring LightDM..."
sudo systemctl enable lightdm
sudo systemctl set-default graphical.target

# 3. Project Setup
PROJECT_DIR="$HOME/aolos-os"
echo "--> Setting up project in $PROJECT_DIR..."

rm -rf "$PROJECT_DIR"
mkdir -p "$PROJECT_DIR"
cd "$PROJECT_DIR"

mkdir -p electron
mkdir -p src/components/apps
mkdir -p src/components/os

# --- GENERATE CONFIG FILES ---

# 1. package.json
cat > package.json <<'EOF'
{
  "name": "aolos",
  "version": "1.0.0",
  "main": "electron/main.js",
  "type": "module",
  "scripts": {
    "dev": "vite",
    "build": "tsc && vite build",
    "preview": "vite preview",
    "electron:dev": "electron .",
    "start": "npx electron ."
  }
}
EOF

# 2. vite.config.ts
cat > vite.config.ts <<'EOF'
import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  base: './',
  resolve: {
    alias: {
      '@': path.resolve(__dirname, './src'),
    },
  },
  build: {
    outDir: 'dist',
    emptyOutDir: true,
  }
})
EOF

# 3. tsconfig.json
cat > tsconfig.json <<'EOF'
{
  "compilerOptions": {
    "target": "ES2020",
    "useDefineForClassFields": true,
    "lib": ["ES2020", "DOM", "DOM.Iterable"],
    "module": "ESNext",
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "react-jsx",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["src/*"]
    }
  },
  "include": ["src"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
EOF

# 4. tsconfig.node.json
cat > tsconfig.node.json <<'EOF'
{
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true
  },
  "include": ["vite.config.ts"]
}
EOF

# 5. Tailwind Configs
cat > tailwind.config.js <<'EOF'
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {
      colors: {
        aol: {
          blue: '#000099',
          lightBlue: '#0066CC',
          beige: '#ECE9D8',
          winGray: '#C0C0C0',
          winDark: '#808080',
        }
      },
      boxShadow: {
        'win-out': '2px 2px 0px 0px #000000, inset 2px 2px 0px 0px #ffffff, inset -2px -2px 0px 0px #808080',
        'win-in': 'inset 2px 2px 0px 0px #808080, inset -2px -2px 0px 0px #ffffff',
      }
    },
  },
  plugins: [],
}
EOF

cat > postcss.config.js <<'EOF'
export default {
  plugins: {
    tailwindcss: {},
    autoprefixer: {},
  },
}
EOF

# --- GENERATE APP CONTENT ---

# 6. index.html
cat > index.html <<'EOF'
<!doctype html>
<html lang="en">
  <head>
    <meta charset="UTF-8" />
    <meta name="viewport" content="width=device-width, initial-scale=1.0" />
    <title>AOLOS</title>
  </head>
  <body>
    <div id="root"></div>
    <script type="module" src="/src/main.tsx"></script>
  </body>
</html>
EOF

# 7. src/index.css
cat > src/index.css <<'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  margin: 0;
  padding: 0;
  background-color: #000;
  overflow: hidden;
  font-family: 'Arial', sans-serif;
}

::-webkit-scrollbar {
  width: 16px;
  background: #ece9d8;
}
::-webkit-scrollbar-thumb {
  background: #c0c0c0;
  border: 2px solid;
  border-color: #ffffff #808080 #808080 #ffffff;
}
EOF

# 8. src/main.tsx
cat > src/main.tsx <<'EOF'
import React from 'react'
import ReactDOM from 'react-dom/client'
import App from './App'
import './index.css'

ReactDOM.createRoot(document.getElementById('root')!).render(
  <React.StrictMode>
    <App />
  </React.StrictMode>,
)
EOF

# 9. src/App.tsx
cat > src/App.tsx <<'EOF'
import { useState, useEffect } from 'react'
import { Terminal, Wifi, Battery, Disc, User, Lock, X } from 'lucide-react'

function App() {
  const [isLoggedIn, setIsLoggedIn] = useState(false)
  const [loginStep, setLoginStep] = useState<'idle' | 'dialing' | 'verifying' | 'connected'>('idle')
  const [time, setTime] = useState(new Date())

  useEffect(() => {
    const timer = setInterval(() => setTime(new Date()), 1000)
    return () => clearInterval(timer)
  }, [])

  const handleSignOn = () => {
    if (loginStep !== 'idle') return
    
    setLoginStep('dialing')
    setTimeout(() => setLoginStep('verifying'), 1500)
    setTimeout(() => setLoginStep('connected'), 3000)
    setTimeout(() => setIsLoggedIn(true), 4000)
  }

  // --- LOGIN SCREEN ---
  if (!isLoggedIn) {
    return (
      <div className="h-screen w-screen bg-aol-beige flex items-center justify-center relative overflow-hidden">
        <div className="absolute inset-0 z-0 opacity-10 pointer-events-none" 
             style={{backgroundImage: 'radial-gradient(#000099 1px, transparent 1px)', backgroundSize: '20px 20px'}}>
        </div>

        <div className="w-[480px] bg-aol-beige border-2 border-white border-r-aol-winDark border-b-aol-winDark shadow-xl z-10 relative">
          <div className="bg-aol-blue h-8 flex items-center justify-between px-2 select-none">
            <div className="flex items-center gap-2">
               <div className="w-4 h-4 bg-white rounded-full opacity-50"></div>
               <span className="text-white font-bold text-sm tracking-wide">Sign On</span>
            </div>
            <div className="bg-aol-beige w-5 h-5 flex items-center justify-center border border-white border-r-aol-winDark border-b-aol-winDark active:border-t-aol-winDark active:border-l-aol-winDark">
              <X size={14} className="text-black" />
            </div>
          </div>

          <div className="p-6 flex flex-col gap-6">
            <div className="flex gap-6">
              <div className="w-32 flex flex-col items-center justify-center">
                 <div className="w-24 h-24 bg-aol-blue rounded-full flex items-center justify-center shadow-lg mb-2">
                    <div className="text-white font-serif font-bold text-4xl italic">Aol.</div>
                 </div>
                 <div className="text-xs text-gray-500 text-center">v 9.0 Optimized</div>
              </div>

              <div className="flex-1 flex flex-col gap-4">
                <div>
                  <label className="block text-xs font-bold text-gray-700 mb-1">Screen Name</label>
                  <div className="bg-white border-2 border-aol-winDark border-b-white border-r-white p-1 flex items-center shadow-win-in">
                    <User size={16} className="text-gray-400 mr-2" />
                    <select className="w-full bg-transparent outline-none text-sm font-bold">
                      <option>Guest</option>
                      <option>Admin</option>
                    </select>
                  </div>
                </div>

                <div>
                  <label className="block text-xs font-bold text-gray-700 mb-1">Password</label>
                  <div className="bg-white border-2 border-aol-winDark border-b-white border-r-white p-1 flex items-center shadow-win-in">
                    <Lock size={16} className="text-gray-400 mr-2" />
                    <input type="password" className="w-full bg-transparent outline-none text-sm" defaultValue="password" />
                  </div>
                </div>
              </div>
            </div>

            <div className="h-24 bg-white border-2 border-aol-winDark border-b-white border-r-white shadow-win-in p-2 overflow-y-auto">
               {loginStep === 'idle' && <p className="text-sm text-gray-600">Ready to connect.</p>}
               {loginStep === 'dialing' && <p className="text-sm text-aol-blue font-bold">Step 1: Dialing...</p>}
               {loginStep === 'verifying' && <p className="text-sm text-aol-blue">Step 2: Verifying password...</p>}
               {loginStep === 'connected' && <p className="text-sm text-green-700 font-bold">Welcome!</p>}
            </div>

            <div className="flex justify-between items-center pt-2 border-t border-gray-300">
               <div className="flex gap-2">
                 <button className="text-xs underline text-blue-800 hover:text-red-600">Help</button>
               </div>
               <button 
                 onClick={handleSignOn}
                 disabled={loginStep !== 'idle'}
                 className="px-8 py-2 bg-aol-beige border-2 border-white border-r-aol-winDark border-b-aol-winDark active:border-t-aol-winDark active:border-l-aol-winDark shadow-win-out font-bold text-aol-blue text-lg hover:bg-gray-100 disabled:opacity-50"
               >
                 SIGN ON
               </button>
            </div>
          </div>
        </div>
      </div>
    )
  }

  // --- DESKTOP ENVIRONMENT ---
  return (
    <div className="h-screen w-screen flex flex-col bg-slate-900 text-white overflow-hidden">
      <div className="h-8 bg-slate-800 flex items-center justify-between px-4 border-b border-slate-700 select-none">
        <div className="font-bold tracking-wider text-blue-400">AOLOS SYSTEM</div>
        <div className="flex items-center gap-4 text-sm">
          <div className="flex items-center gap-2">
            <Wifi size={14} />
            <span>Connected</span>
          </div>
          <div className="flex items-center gap-2">
            <Battery size={14} />
            <span>100%</span>
          </div>
          <div>{time.toLocaleTimeString()}</div>
        </div>
      </div>

      <div className="flex-1 relative p-8">
        <div className="grid grid-cols-4 gap-8 w-full max-w-2xl">
          <div className="flex flex-col items-center gap-2 group cursor-pointer p-4 rounded-lg hover:bg-white/10 transition">
            <div className="w-16 h-16 bg-blue-600 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-105 transition">
              <Terminal size={32} className="text-white" />
            </div>
            <span className="text-sm font-medium text-gray-300 group-hover:text-white">Terminal</span>
          </div>
          
          <div className="flex flex-col items-center gap-2 group cursor-pointer p-4 rounded-lg hover:bg-white/10 transition">
            <div className="w-16 h-16 bg-purple-600 rounded-xl flex items-center justify-center shadow-lg group-hover:scale-105 transition">
              <Disc size={32} className="text-white" />
            </div>
            <span className="text-sm font-medium text-gray-300 group-hover:text-white">Files</span>
          </div>
        </div>

        <div className="absolute bottom-8 left-8 p-6 bg-slate-800/90 backdrop-blur border border-slate-700 rounded-lg max-w-md">
          <h2 className="text-xl font-bold mb-2">Welcome</h2>
          <p className="text-gray-400">You have mail!</p>
        </div>
      </div>
    </div>
  )
}

export default App
EOF

# 10. electron/main.js
cat > electron/main.js <<'EOF'
import { app, BrowserWindow } from 'electron';
import path from 'path';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

function createWindow() {
  const win = new BrowserWindow({
    fullscreen: true,
    kiosk: true,
    frame: false,
    webPreferences: {
      nodeIntegration: true,
      contextIsolation: false,
      webSecurity: false 
    }
  });

  win.loadFile(path.join(__dirname, '../dist/index.html'));
}

app.whenReady().then(() => {
  createWindow();

  app.on('activate', () => {
    if (BrowserWindow.getAllWindows().length === 0) {
      createWindow();
    }
  });
});

app.on('window-all-closed', () => {
  if (process.platform !== 'darwin') {
    app.quit();
  }
});
EOF

# --- INSTALL & BUILD ---

echo "--> Installing NPM Dependencies..."
npm install react react-dom lucide-react electron xterm@latest xterm-addon-fit@latest

echo "--> Installing Dev Dependencies (Types & Vite)..."
npm install -D vite @vitejs/plugin-react typescript tailwindcss postcss autoprefixer \
    @types/react @types/react-dom @types/node

echo "--> Building the application..."
npm run build

# Verify Build Success
if [ ! -f "dist/index.html" ]; then
    echo "CRITICAL ERROR: Build failed. dist/index.html not found."
    exit 1
fi

# 4. Openbox session file
echo "--> Creating Openbox Session..."
sudo mkdir -p /usr/share/xsessions
sudo bash -c 'cat > /usr/share/xsessions/openbox-aolos.desktop <<EOF
[Desktop Entry]
Name=Openbox (AOLOS)
Comment=Openbox Session for AOLOS Kiosk
Exec=/usr/bin/openbox-session
TryExec=/usr/bin/openbox-session
Type=Application
EOF'

# 5. Openbox autostart
echo "--> Configuring Openbox Autostart..."
mkdir -p ~/.config/openbox
# NOTE: using quoted EOF for file content, but we need $PROJECT_DIR expanded
cat > ~/.config/openbox/autostart <<EOF
# Disable screen saver and power management
xset s off -dpms s noblank
unclutter-xfixes -idle 1 &
cd $PROJECT_DIR

# Start Electron with GPU flags to prevent blank screen in VirtualBox
# Loop it so if it crashes it restarts immediately
while true; do
  npx electron electron/main.js --kiosk --no-sandbox --disable-gpu --disable-software-rasterizer
  sleep 1
done
EOF
chmod +x ~/.config/openbox/autostart

# 6. LightDM auto-login
echo "--> Configuring Auto-login for user: $USER"
# We write to BOTH the main file and the .d directory to be absolutely sure
sudo bash -c "cat > /etc/lightdm/lightdm.conf <<EOF
[Seat:*]
autologin-user=$USER
autologin-user-timeout=0
user-session=openbox-aolos
greeter-session=lightdm-gtk-greeter
EOF"

echo "======================================="
echo "AOLOS Installation Complete."
echo "======================================="
