import os
import sys
import stat
import time
import shutil
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

        # The "lib" folder is updated on every release, so instead of
        # merging the new files into the old folder (which would leave
        # stale files behind), the whole folder is replaced.
        self.lib_dir_name = "lib"
        self.lib_path = os.path.join(self.extract_path, self.lib_dir_name)
        self.lib_backup_path = os.path.join(
            self.extract_path, self.lib_dir_name + "_old"
        )

        # Name of the file this program is currently running as (only set
        # when frozen into an .exe, e.g. via PyInstaller). If the zip
        # contains a file with this same name, Windows will refuse to
        # overwrite it because the running process has it locked - this is
        # what causes "[Errno 13] Permission denied: 'unzip.exe'".
        self.self_exe_name = None
        if getattr(sys, "frozen", False):
            self.self_exe_name = os.path.basename(sys.executable)

        # unzip.exe is also updated on every release. A running .exe
        # cannot be overwritten or deleted, but Windows DOES allow it to be
        # renamed. So the running exe is renamed to "<name>.old", the new
        # one is extracted under the real name, and the ".old" file is
        # deleted once this process has exited (or on the next run).
        self.self_exe_backup_path = None
        if self.self_exe_name:
            self.self_exe_backup_path = os.path.join(
                self.extract_path, self.self_exe_name + ".old"
            )

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

    # ------------------------------------------------------------------
    # lib folder replacement helpers
    # ------------------------------------------------------------------
    def is_lib_entry(self, name):
        """True if the zip entry lives inside the 'lib' folder."""
        parts = name.replace("\\", "/").lstrip("/").split("/")
        return len(parts) > 1 and parts[0].lower() == self.lib_dir_name

    @staticmethod
    def _on_rmtree_error(func, path, exc_info):
        # Clear the read-only flag and retry once (common on Windows).
        try:
            os.chmod(path, stat.S_IWRITE)
            func(path)
        except Exception:
            raise

    def remove_dir(self, path, retries=5, delay=0.5):
        """Delete a folder, retrying because files may be released slowly
        (the main app may still be closing, antivirus may be scanning)."""
        for _ in range(retries):
            if not os.path.exists(path):
                return True
            try:
                shutil.rmtree(path, onerror=self._on_rmtree_error)
                return True
            except Exception:
                time.sleep(delay)
        return not os.path.exists(path)

    def rename_dir(self, src, dst, retries=5, delay=0.5):
        for _ in range(retries):
            try:
                os.rename(src, dst)
                return True
            except OSError:
                time.sleep(delay)
        return False

    def prepare_lib_replacement(self):
        """Move the current lib folder out of the way.

        Returns True if the old folder was kept as a backup (so it can be
        restored if extraction fails), False if there was nothing to back
        up or the old folder had to be deleted instead.
        """
        # Leftover backup from an earlier interrupted update.
        if os.path.exists(self.lib_backup_path):
            self.remove_dir(self.lib_backup_path)

        if not os.path.exists(self.lib_path):
            return False

        if self.rename_dir(self.lib_path, self.lib_backup_path):
            return True

        # Could not rename (some file inside is locked). Fall back to
        # deleting whatever can be deleted; the extraction below will
        # overwrite anything that is left.
        self.remove_dir(self.lib_path, retries=3)
        return False

    def restore_lib_backup(self):
        """Roll back to the previous lib folder after a failed update."""
        if not os.path.exists(self.lib_backup_path):
            return
        self.remove_dir(self.lib_path)
        self.rename_dir(self.lib_backup_path, self.lib_path)

    def discard_lib_backup(self):
        if os.path.exists(self.lib_backup_path):
            self.remove_dir(self.lib_backup_path)

    # ------------------------------------------------------------------
    # unzip.exe (this updater) replacement helpers
    # ------------------------------------------------------------------
    def is_self_entry(self, name):
        """True if the zip entry is this updater's own exe (root level)."""
        if not self.self_exe_name:
            return False
        normalized = name.replace("\\", "/").lstrip("/").lower()
        return normalized == self.self_exe_name.lower()

    def cleanup_self_backup(self):
        """Delete a leftover '<name>.old' from a previous update."""
        if self.self_exe_backup_path and os.path.exists(self.self_exe_backup_path):
            try:
                os.remove(self.self_exe_backup_path)
            except OSError:
                pass

    def prepare_self_replacement(self):
        """Rename the running exe out of the way.

        Returns "moved"  - renamed to .old, the new exe can be extracted
                "absent" - no exe on disk, simply extract the new one
                "locked" - could not rename, the exe must be skipped
        """
        target = os.path.join(self.extract_path, self.self_exe_name)
        if not os.path.exists(target):
            return "absent"

        self.cleanup_self_backup()
        if self.rename_dir(target, self.self_exe_backup_path, retries=3):
            return "moved"
        return "locked"

    def restore_self_backup(self):
        """Put the old exe back after a failed update."""
        if not os.path.exists(self.self_exe_backup_path):
            return
        target = os.path.join(self.extract_path, self.self_exe_name)
        try:
            if os.path.exists(target):
                os.remove(target)
        except OSError:
            pass
        self.rename_dir(self.self_exe_backup_path, target, retries=3)

    def schedule_self_backup_deletion(self):
        """Delete '<name>.old' after this process has exited."""
        if os.name != "nt" or not self.self_exe_backup_path:
            return
        path = os.path.abspath(self.self_exe_backup_path)
        flags = getattr(subprocess, "CREATE_NO_WINDOW", 0)
        try:
            subprocess.Popen(
                f'cmd /c ping 127.0.0.1 -n 4 >nul & del /f /q "{path}"',
                creationflags=flags,
                close_fds=True,
            )
        except Exception:
            # Not critical: the next update run will clean it up.
            pass

    # ------------------------------------------------------------------
    def run_update_process(self):
        lib_backup_made = False
        self_backup_made = False
        self_old_pending = False
        try:
            self.cleanup_self_backup()

            if not os.path.exists(self.zip_path):
                error_msg = f"The required file '{self.zip_path}' was not found."
                self.update_status("Update failed.", 0)
                wx.CallAfter(self.show_error_dialog, error_msg)
                return

            skipped_files = []
            with zipfile.ZipFile(self.zip_path, "r") as zip_ref:
                files = zip_ref.namelist()
                total_files = len(files)

                # Only replace the lib folder if the new zip actually
                # contains one, so a broken/partial zip never wipes it.
                has_lib = any(self.is_lib_entry(f) for f in files)
                if has_lib:
                    self.update_status("Replacing lib folder...", 10)
                    lib_backup_made = self.prepare_lib_replacement()

                # Same idea for this updater's own exe: rename the running
                # file so the new one can be written under the real name.
                self_state = None
                if any(self.is_self_entry(f) for f in files):
                    self.update_status("Replacing updater...", 15)
                    self_state = self.prepare_self_replacement()
                    self_backup_made = self_state == "moved"

                self.update_status("Extracting files...", 20)
                for index, file in enumerate(files, start=1):
                    progress = int(20 + (60 * (index / total_files)))

                    # If the running exe could not be renamed, skip it -
                    # Windows keeps it locked and overwriting it would raise
                    # PermissionError (Errno 13).
                    if self.is_self_entry(file) and self_state == "locked":
                        skipped_files.append(file)
                        self.update_status(f"Skipping (in use): {file}", progress)
                        continue

                    try:
                        zip_ref.extract(file, self.extract_path)
                    except PermissionError:
                        # Files inside lib, and the new updater exe, must be
                        # extracted, so a failure there aborts (and rolls
                        # back) the update.
                        if self.is_lib_entry(file) or self.is_self_entry(file):
                            raise
                        # Some other file (e.g. locked by antivirus or by
                        # VDHMediaCenter.exe still running) - don't abort
                        # the whole update, just skip it and continue.
                        skipped_files.append(file)

                    self.update_status(f"Extracting: {file}", progress)

            # Extraction succeeded: the old updater exe is only kept until
            # this process exits, then it is deleted.
            if self_backup_made:
                self_backup_made = False
                self_old_pending = True

            # The old lib folder is no longer needed.
            if lib_backup_made:
                self.update_status("Cleaning up old lib folder...", 82)
                self.discard_lib_backup()
                lib_backup_made = False

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
            if self_old_pending:
                self.schedule_self_backup_deletion()
            wx.CallAfter(self.finish_and_exit)

        except Exception as e:
            if lib_backup_made:
                self.update_status("Restoring previous lib folder...", 0)
                self.restore_lib_backup()
            if self_backup_made:
                self.update_status("Restoring previous updater...", 0)
                self.restore_self_backup()
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
