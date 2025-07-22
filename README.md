# apple-podcast-transcript-downloader
Takes in a podcast ID and downloads the TTML file for the transcript

```
clang -Wno-objc-method-access -framework Foundation -F/System/Library/PrivateFrameworks -framework AppleMediaServices FetchTranscript.m -o FetchTranscript
```

```
./FetchTranscript 1000714478537 --cache-bearer-token
```