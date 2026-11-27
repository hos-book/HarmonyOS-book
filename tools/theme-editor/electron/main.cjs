const { app, BrowserWindow } = require('electron');
const path = require('node:path');

function openEditor() {
  const window = new BrowserWindow({
    width: 1480,
    height: 960,
    minWidth: 900,
    minHeight: 680,
    backgroundColor: '#f5f3ef',
    autoHideMenuBar: true,
    webPreferences: { contextIsolation: true, sandbox: true, nodeIntegration: false }
  });
  window.webContents.session.on('will-download', (_event, item) => {
    item.setSaveDialogOptions({ title: '导出简听主题', defaultPath: item.getFilename() });
  });
  window.loadFile(path.join(__dirname, '../dist/index.html'));
}

app.whenReady().then(openEditor);
app.on('activate', () => { if (BrowserWindow.getAllWindows().length === 0) openEditor(); });
app.on('window-all-closed', () => { if (process.platform !== 'darwin') app.quit(); });
