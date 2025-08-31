# Auto Video Converter

This PowerShell script automatically monitors a specified source folder for new video files, converts them using FFmpeg with NVIDIA CUDA acceleration, extracts subtitles, and moves the processed files to a target folder. It's designed for hands-free video processing, especially useful for converting downloaded videos to a consistent format.

## Features

- **Automatic Monitoring**: Watches a source directory for newly created video files.
- **FFmpeg Integration**: Utilizes FFmpeg for robust video conversion.
- **CUDA Acceleration**: Leverages NVIDIA GPUs for faster encoding (H.264 NVENC).
- **Subtitle Management**: Automatically extracts subtitle tracks from video files for specified languages. It also converts standalone subtitle files (e.g., `.ass`, `.vtt`) to the standard `.srt` format.
- **File Size Stabilization**: Waits for files to be fully written before starting conversion, preventing issues with incomplete downloads.
- **Smart File Copying**: Copies original and converted files to a destination folder by intelligently matching file names to subfolder names.
- **Configurable**: All paths, extensions, and conversion parameters are customizable via a `config.yaml` file.
- **Logging**: Records all actions and errors to a specified log file.
- **Telegram Notifications**: Sends real-time updates on video downloads and conversion completion to a Telegram channel and can notify a specific user about copy operations.
- **Automatic Updates**: Can automatically check for new versions on GitHub and update itself.
- **Error Handling**: Includes checks for missing paths, FFmpeg, and parsing errors.

## Requirements

- **PowerShell**: Version 5.1 or higher (comes pre-installed on Windows).
- **FFmpeg**: Must be installed and the path to `ffmpeg.exe` specified in the `config.yaml` file.
- **NVIDIA GPU (Optional but Recommended)**: For CUDA acceleration, an NVIDIA GPU with compatible drivers is required.
- **powershell-yaml**: The script will attempt to install this module automatically.

## Installation

1. **Clone the repository** (or download the script):

    ```bash
    git clone https://github.com/neiromaster/auto-converter.git
    cd auto-converter
    ```

2. **Install FFmpeg**: Download the latest FFmpeg build from [ffmpeg.org](https://ffmpeg.org/download.html) and extract it to a location on your system. Note the path to `ffmpeg.exe`.
3. **Create `config.yaml` file**: Create a file named `config.yaml` in the root directory of the project (where `auto-converter.ps1` is located). See the [Configuration](#configuration) section for details.
4. **Create `.env` file**: Create a file named `.env` in the project root for storing Telegram secrets.

## Configuration

Create a `config.yaml` file in the project root with the following structure:

```yaml
paths:
  source_folder: D:\disc\YandexDisk\sync
  target_folder: D:\disc\YandexDisk\sync
  temp_folder: '%TEMP%'
  destination_folder: D:\disc2\Yandex.Disk\Равки 2 # Optional: for smart copying

settings:
  min_file_size_mb: 800
  prefix: жат-
  ignore_prefix: жат-
  telegram_enabled: true
  auto_update_enabled: true # Set to false to disable automatic updates

ffmpeg:
  ffmpeg_path: D:/scoop/shims/ffmpeg.exe

video_extensions:
  - .mp4
  - .avi
  - .mov
  - .wmv
  - .flv
  - .webm
  - .mkv
  - .m4v

subtitle_extension:
  - .vtt
  - .srt
  - .ass

subtitles:
  extract_languages:
    - rus
    - eng

stabilization_strategy:
  use_file_size_stabilization: true
  stabilization_check_interval_sec: 5
  stabilization_timeout_sec: 600

logging:
  log_file: auto-converter.log
```

Create a `.env` file in the project root for your Telegram Bot Token and chat IDs:

```ini
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"
TELEGRAM_CHANNEL_ID=-1001234567890 # ID of the channel for general notifications
TELEGRAM_CHAT_ID=123456789 # Your personal Chat ID for notifications about file copy operations
```

**Important Notes for Telegram:**

- To get a `TELEGRAM_BOT_TOKEN`, talk to BotFather on Telegram and create a new bot.
- To get your `TELEGRAM_CHANNEL_ID`, add your bot to a channel as an administrator. Then, send a message to the channel and use `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates` in your browser. Look for the `chat` object and its `id` field.
- To get your personal `TELEGRAM_CHAT_ID`, send a message to your bot and use the same `getUpdates` URL. Look for the `chat` object and its `id` from your personal message.

## Usage

To run the script, open PowerShell and navigate to the project directory, then execute:

```powershell
.\auto-converter.ps1
```

The script will start monitoring the `SOURCE_FOLDER`. To stop the script, press `Ctrl+C`.

## How it Works

1. **Loads Configuration**: Reads settings from `config.yaml` and `.env` files.
2. **Checks for Updates**: If `auto_update_enabled` is true, the script checks for a new version on GitHub. If found, it downloads and applies the update, then restarts itself.
3. **Monitors Source Folder**: Uses `FileSystemWatcher` to detect new files.
4. **Handles Subtitles**: If a new file is a standalone subtitle file (e.g., `.ass`), it's automatically converted to `.srt`.
5. **File Stabilization**: For video files, it continuously checks the file size until it stabilizes, ensuring the file is fully downloaded/copied.
6. **Smart Copying (Pre-conversion)**: If `destination_folder` is set, the script searches for a subfolder within it whose name partially matches the new video file's name. It then copies the original video file to that subfolder.
7. **Subtitle Extraction**: If a video has subtitle tracks with languages specified in `subtitles.extract_languages`, they will be extracted as `.srt` files.
8. **FFmpeg Conversion**: Once a video file is detected and stable, it uses FFmpeg to convert it. It attempts to use `cuvid` for decoding and `h264_nvenc` for encoding if an NVIDIA GPU is present.
- **Moves to Target**: After successful conversion, the new file is moved to the `TARGET_FOLDER`.
- **Smart Copying (Post-conversion)**: The newly converted file is also copied to the same matched subfolder within `destination_folder`.
- **Logging & Notifications**: Logs all significant events. Sends notifications to `TELEGRAM_CHANNEL_ID` about downloads and conversions, and to `TELEGRAM_CHAT_ID` about the results of copy operations.

## Project Structure

The project includes a `builder.ps1` script. This script is used for development to bundle the main `auto-converter.ps1` script and all its modules from the `includes` directory into a single, distributable `dist/auto-converter.ps1` file. You do not need to run it for normal use.

## Troubleshooting

- **`FFmpeg not found`**: Ensure `ffmpeg_path` in your `config.yaml` file points to the correct `ffmpeg.exe` location.
- **`Path does not exist`**: Verify that `source_folder`, `target_folder`, and `temp_folder` paths in your `config.yaml` are correct and accessible.
- **`Error parsing settings`**: Check your `config.yaml` file for correct structure and data types.
- **Conversion issues**: Check the log file for FFmpeg errors. Ensure your NVIDIA drivers are up to date if using CUDA acceleration.
- **Telegram messages not sending**: Double-check your `TELEGRAM_BOT_TOKEN`, `TELEGRAM_CHANNEL_ID`, and `TELEGRAM_CHAT_ID` in the `.env` file. Ensure your bot has the necessary permissions.