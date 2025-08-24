# Auto Video Converter

This PowerShell script automatically monitors a specified source folder for new video files, converts them using FFmpeg with NVIDIA CUDA acceleration, and moves the processed files to a target folder. It's designed for hands-free video processing, especially useful for converting downloaded videos to a consistent format.

## Features

- **Automatic Monitoring**: Watches a source directory for newly created video files.
- **FFmpeg Integration**: Utilizes FFmpeg for robust video conversion.
- **CUDA Acceleration**: Leverages NVIDIA GPUs for faster encoding (H.264 NVENC).
- **File Size Stabilization**: Waits for files to be fully written before starting conversion, preventing issues with incomplete downloads.
- **Configurable**: All paths, extensions, and conversion parameters are customizable via a `.env` file.
- **Logging**: Records all actions and errors to a specified log file.
- **Telegram Notifications**: Sends real-time updates on video downloads and conversion completion to a Telegram chat.
- **Error Handling**: Includes checks for missing paths, FFmpeg, and parsing errors.

## Requirements

- **PowerShell**: Version 5.1 or higher (comes pre-installed on Windows).
- **FFmpeg**: Must be installed and the path to `ffmpeg.exe` specified in the `.env` file.
- **NVIDIA GPU (Optional but Recommended)**: For CUDA acceleration, an NVIDIA GPU with compatible drivers is required.

## Installation

1.  **Clone the repository** (or download the script):
    ```bash
    git clone https://github.com/neiromaster/auto-converter.git
    cd auto-converter
    ```
2.  **Install FFmpeg**: Download the latest FFmpeg build from [ffmpeg.org](https://ffmpeg.org/download.html) and extract it to a location on your system. Note the path to `ffmpeg.exe`.
3.  **Create `.env` file**: Create a file named `.env` in the root directory of the project (where `auto-converter.ps1` is located). See the [Configuration](#configuration) section for details.

## Configuration

Create a `.env` file in the project root with the following variables:

```ini
# --- Folder Paths ---
SOURCE_FOLDER="C:\Path\To\Your\SourceVideos"       # Folder to monitor for new videos
TARGET_FOLDER="C:\Path\To\Your\ConvertedVideos"    # Folder where converted videos will be saved
TEMP_FOLDER="C:\Path\To\Your\Temp"                 # Temporary folder for intermediate files

# --- FFmpeg Settings ---
FFMPEG_PATH="C:\ffmpeg\bin\ffmpeg.exe"             # Absolute path to ffmpeg.exe
VIDEO_EXTENSIONS=".mp4,.mkv,.avi,.mov"             # Comma-separated list of video extensions to process
PREFIX="converted_"                                # Prefix for converted file names (e.g., converted_video.mkv)
IGNORE_PREFIX="temp_"                              # Files starting with this prefix will be ignored

# --- File Stabilization ---
USE_FILE_SIZE_STABILIZATION=true                   # Set to "true" to enable, "false" to disable
MIN_FILE_SIZE_MB=10                                # Minimum file size in MB to start processing
STABILIZATION_CHECK_INTERVAL_SEC=5                 # How often to check file size during stabilization
STABILIZATION_TIMEOUT_SEC=300                      # Max time (seconds) to wait for file size stabilization
STABILIZATION_TOLERANCE_BYTES=1024                 # Max byte difference to consider file size stable

# --- Logging ---
LOG_ENABLED=true                                   # Set to "true" to enable logging, "false" to disable
LOG_FILE="C:\Path\To\Your\auto-converter.log"      # Absolute path for the log file

# --- Telegram Notifications (Optional) ---
TELEGRAM_ENABLED=false                             # Set to "true" to enable Telegram notifications
TELEGRAM_BOT_TOKEN="YOUR_TELEGRAM_BOT_TOKEN"       # Your Telegram Bot API Token
TELEGRAM_CHANNEL_ID=-1234567890                    # Your Telegram Channel ID (e.g., -1001234567890 for a channel)
```

**Important Notes for Telegram:**
- To get a `TELEGRAM_BOT_TOKEN`, talk to BotFather on Telegram and create a new bot.
- To get your `TELEGRAM_CHANNEL_ID`, add your bot to a channel as an administrator. Then, send a message to the channel and use `https://api.telegram.org/bot<YOUR_BOT_TOKEN>/getUpdates` in your browser. Look for the `chat` object and its `id` field (it will be a negative number for channels).

## Usage

To run the script, open PowerShell and navigate to the project directory, then execute:

```powershell
.\auto-converter.ps1
```

The script will start monitoring the `SOURCE_FOLDER`. To stop the script, press `Ctrl+C`.

## How it Works

1.  **Loads Configuration**: Reads settings from the `.env` file.
2.  **Monitors Source Folder**: Uses `FileSystemWatcher` to detect new files.
3.  **File Stabilization**: If enabled, it continuously checks the file size until it stabilizes, ensuring the file is fully downloaded/copied.
4.  **FFmpeg Conversion**: Once a video file is detected and stable, it uses FFmpeg to convert it. It attempts to use `cuvid` for decoding and `h264_nvenc` for encoding if an NVIDIA GPU is present.
5.  **Moves to Target**: After successful conversion, the new file is moved to the `TARGET_FOLDER`.
6.  **Logging & Notifications**: Logs all significant events and sends Telegram notifications if configured.

## Troubleshooting

-   **`FFmpeg not found`**: Ensure `FFMPEG_PATH` in your `.env` file points to the correct `ffmpeg.exe` location.
-   **`Path does not exist`**: Verify that `SOURCE_FOLDER`, `TARGET_FOLDER`, `TEMP_FOLDER`, and `LOG_FILE` paths in your `.env` are correct and accessible.
-   **`Error parsing settings`**: Check your `.env` file for correct variable types (e.g., `true`/`false` for booleans, numbers for integers).
-   **Conversion issues**: Check the log file for FFmpeg errors. Ensure your NVIDIA drivers are up to date if using CUDA acceleration.
-   **Telegram messages not sending**: Double-check your `TELEGRAM_BOT_TOKEN` and `TELEGRAM_CHANNEL_ID` in the `.env` file. Ensure your bot has admin rights in the channel.

For further assistance, please refer to the script's source code (`auto-converter.ps1`) for detailed logic and error messages.