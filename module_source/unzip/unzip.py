import os
import sys
import subprocess
import threading
import zipfile
import wx


class UpdaterFrame(wx.Frame):

    def __init__(self):
        super().__init__(
            parent=None,
            title="Updater",
            size=(420, 200),
            style=wx.DEFAULT_FRAME_STYLE
            & ~(wx.RESIZE_BORDER | wx.MAXIMIZE_BOX),
        )

        self.zip_path = "vdh_media_center.zip"
        self.extract_path = "."
        self.exe_path = "VDHMediaCenter.exe"

        # Name of the file this program is currently running as (only set
        # when frozen into an .exe, e.g. via PyInstaller). If the zip
        # contains a file with this same name, Windows will refuse to
        # overwrite it because the running process has it locked - this is
        # what causes "[Errno 13] Permission denied: 'unzip.exe'".
        self.self_exe_name = None
        if getattr(sys, "frozen", False):
            self.self_exe_name = os.path.basename(sys.executable)

        self.InitUI()
        self.Centre()

        threading.Thread(target=self.run_update_process, daemon=True).start()

    def InitUI(self):
        panel = wx.Panel(self)
        sizer = wx.BoxSizer(wx.VERTICAL)

        self.label_status = wx.StaticText(
            panel,
            label="Updating is in progress, please do not close this window",
            style=wx.ALIGN_CENTER,
        )
        font_status = wx.Font(
            10, wx.FONTFAMILY_DEFAULT, wx.FONTSTYLE_NORMAL, wx.FONTWEIGHT_BOLD
        )
        self.label_status.SetFont(font_status)

        self.progress_bar = wx.Gauge(panel, range=100, size=(340, 20))

        self.label_detail = wx.StaticText(
            panel, label="Initializing process...", style=wx.ALIGN_CENTER
        )
        font_detail = wx.Font(
            9, wx.FONTFAMILY_DEFAULT, wx.FONTSTYLE_NORMAL, wx.FONTWEIGHT_NORMAL
        )
        self.label_detail.SetFont(font_detail)
        self.label_detail.SetForegroundColour(wx.Colour(100, 100, 100))

        sizer.Add(self.label_status, 0, wx.ALL | wx.EXPAND, 15)
        sizer.Add(
            self.progress_bar, 0, wx.ALIGN_CENTER_HORIZONTAL | wx.BOTTOM, 15
        )
        sizer.Add(self.label_detail, 0, wx.ALL | wx.EXPAND, 5)

        panel.SetSizer(sizer)

    def show_error_dialog(self, message):
        wx.MessageBox(
            message,
            "Update Error",
            wx.OK | wx.ICON_ERROR,
            parent=self,
        )
        self.close_application()

    def close_application(self):
        self.Destroy()
        wx.GetApp().ExitMainLoop()

    def finish_and_exit(self):
        wx.CallLater(1000, self.close_application)

    def run_update_process(self):
        try:
            if not os.path.exists(self.zip_path):
                error_msg = f"The required file '{self.zip_path}' was not found."
                self.update_status("Update failed.", 0)
                wx.CallAfter(self.show_error_dialog, error_msg)
                return

            self.update_status("Extracting files...", 20)
            skipped_files = []
            with zipfile.ZipFile(self.zip_path, "r") as zip_ref:
                files = zip_ref.namelist()
                total_files = len(files)
                for index, file in enumerate(files, start=1):
                    # Never try to overwrite the exe that is currently
                    # running this updater - Windows keeps it locked and
                    # this raises PermissionError (Errno 13).
                    if self.self_exe_name and os.path.basename(file) == self.self_exe_name:
                        skipped_files.append(file)
                        progress = int(20 + (60 * (index / total_files)))
                        self.update_status(f"Skipping (in use): {file}", progress)
                        continue

                    try:
                        zip_ref.extract(file, self.extract_path)
                    except PermissionError:
                        # Some other file (e.g. locked by antivirus or by
                        # VDHMediaCenter.exe still running) - don't abort
                        # the whole update, just skip it and continue.
                        skipped_files.append(file)

                    progress = int(20 + (60 * (index / total_files)))
                    self.update_status(f"Extracting: {file}", progress)

            self.update_status("Removing zip archive...", 85)
            if os.path.exists(self.zip_path):
                os.remove(self.zip_path)

            self.update_status("Launching application...", 95)
            if os.path.exists(self.exe_path):
                subprocess.Popen([self.exe_path])
            else:
                error_msg = f"The application executable '{self.exe_path}' was not found."
                self.update_status("Update failed.", 95)
                wx.CallAfter(self.show_error_dialog, error_msg)
                return

            self.update_status("Done!", 100)
            wx.CallAfter(self.finish_and_exit)

        except Exception as e:
            error_msg = f"An unexpected error occurred:\n{str(e)}"
            self.update_status("Update failed.", 0)
            wx.CallAfter(self.show_error_dialog, error_msg)

    def update_status(self, text, progress):
        wx.CallAfter(self._set_status, text, progress)

    def _set_status(self, text, progress):
        self.label_detail.SetLabel(text)
        self.progress_bar.SetValue(progress)


if __name__ == "__main__":
    app = wx.App(False)
    frame = UpdaterFrame()
    frame.Show()
    app.MainLoop()