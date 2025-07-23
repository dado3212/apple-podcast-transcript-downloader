# Apple Podcast Transcript Downloader

This takes in a podcast ID and downloads the TTML file for the transcript. Use `--cache-bearer-token` to locally cache the necessary credentials for 30 days (useful if you're running this for multiple podcast IDs).

> [!WARNING]
> This is currently only tested on macOS 15.5, and **confirmed to not work on macOS 14.4.1.**

```
abeals@Alexs-MacBook-Pro apple-podcast-transcript-fetcher % ./FetchTranscript --help
FetchTranscript version 1.1.0

Usage:
  FetchTranscript <podcastId> [--cache-bearer-token]

Options:
  --cache-bearer-token   Use cached Bearer token if valid for 30 days, reducing the number of requests
  --help                 Show this help message
```

You can get the podcast ID from the final query in the share link. For instance, https://podcasts.apple.com/us/podcast/if-you-care-about-food-you-have-to-care-about-land/id1728932037?i=1000714478537 corresponds to 1000714478537.

```
./FetchTranscript 1000714478537 --cache-bearer-token
```

<img width="992" height="326" alt="Screenshot 2025-07-22 at 12 54 58 AM" src="https://github.com/user-attachments/assets/de653478-fc50-44a0-bc13-285a6c64a7da" />

You can use this in conjunction with my other tool, https://alexbeals.com/projects/podcasts/, by dragging and dropping the TTML file to browse and copy sections of it.

## Build Instructions
```
clang -Wno-objc-method-access -framework Foundation -F/System/Library/PrivateFrameworks -framework AppleMediaServices FetchTranscript.m -o FetchTranscript
```
