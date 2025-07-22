#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>

#define CACHE_PATH "bearer_token.txt"
#define CACHE_VALIDITY (60 * 60 * 24 * 30) // 30 days in seconds

// This uses pipes because it can segfault, and this wraps that
NSString *fetchBearerToken() {
  int pipefd[2];
  pipe(pipefd);

  pid_t pid = fork();
  if (pid == 0) {
    // Child
    close(pipefd[0]); // Close read end
    dup2(pipefd[1], STDOUT_FILENO);
    close(pipefd[1]);

    @autoreleasepool {

      // Make sure that we can load everything correctly.
      dlopen("/System/Library/PrivateFrameworks/PodcastsFoundation.framework/PodcastsFoundation", RTLD_LAZY);
      Class AMSMescal = objc_getClass("AMSMescal");
      Class AMSMescalSession = objc_getClass("AMSMescalSession");
      Class AMSURLRequestClass = objc_getClass("AMSURLRequest");
      Class IMURLBag = objc_getClass("IMURLBag");

      if (!AMSMescal || !AMSMescalSession || !AMSURLRequestClass || !IMURLBag) {
        if (!IMURLBag) {
          fprintf(stderr, "The PodcastsFoundation dynamic linking failed.\n");
        } else {
          fprintf(stderr, "Missing required classes\n");
        }
        exit(1);
      }

      // The storefront is constant
      NSString *storeFront = @"143441-1,42 t:podcasts1";
      // But load the current date to use for the request
      NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
      [formatter setDateFormat:@"yyyy-MM-dd'T'HH:mm:ss'Z'"];
      [formatter setTimeZone:[NSTimeZone timeZoneWithAbbreviation:@"UTC"]];
      NSString *timestamp = [formatter stringFromDate:[NSDate date]];
      // I'm not sure if the OS version needs to match
      NSURL *tokenURL = [NSURL URLWithString:@"https://sf-api-token-service.itunes.apple.com/apiToken?clientClass=apple&clientId=com.apple.podcasts.macos&os=OS%20X&osVersion=15.5&productVersion=1.1.0&version=2"];
      NSMutableURLRequest *nsRequest = [NSMutableURLRequest requestWithURL:tokenURL];

      id urlRequest = [[AMSURLRequestClass alloc] initWithRequest:nsRequest];
      [urlRequest setValue:timestamp forHTTPHeaderField:@"x-request-timestamp"];
      [urlRequest setValue:storeFront forHTTPHeaderField:@"X-Apple-Store-Front"];

      id signature = [AMSMescal _signedActionDataFromRequest:urlRequest policy:@{
        @"fields": @[@"clientId"],
        @"headers": @[
          @"x-apple-store-front",
          @"x-apple-client-application",
          @"x-request-timestamp"
        ]
      }];

      id session = [AMSMescalSession defaultSession];
      id urlBag = [[IMURLBag alloc] init];

      dispatch_semaphore_t sema = dispatch_semaphore_create(0);

      id signedPromise = [session signData:signature bag:urlBag];
      [signedPromise thenWithBlock:^(id result) {
        NSString *xAppleActionSignature = [(NSData *)result base64EncodedStringWithOptions:0];

        NSMutableURLRequest *signedRequest = [NSMutableURLRequest requestWithURL:tokenURL];
        [signedRequest setValue:timestamp forHTTPHeaderField:@"x-request-timestamp"];
        [signedRequest setValue:storeFront forHTTPHeaderField:@"X-Apple-Store-Front"];
        [signedRequest setValue:xAppleActionSignature forHTTPHeaderField:@"X-Apple-ActionSignature"];

        NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:signedRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) { 
          NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
          
          printf("%s\n", [json[@"token"] UTF8String]);

          dispatch_semaphore_signal(sema);
        }];
        [task resume];

        // The double semaphore is a little janky, but it helps paper over a bug where
        // my incorrect invocation of thenWithBlock eventually segfaults when it tries
        // to do cleanup.
        dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
      }];

      dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
    }

    exit(0);
  }

  // Parent
  close(pipefd[1]); // Close write end
  char buffer[4096] = {0};
  read(pipefd[0], buffer, sizeof(buffer) - 1);
  close(pipefd[0]);

  int status;
  waitpid(pid, &status, 0);
  if (WIFEXITED(status) && WEXITSTATUS(status) == 0) {
    return [[NSString stringWithUTF8String:buffer] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
  } else {
    return nil;
  }
}


// Will cache bearer_token.txt for 30 days if you use the --cache-bearer-token flag
NSString* getBearerToken(BOOL useCache) {
  NSString *path = [NSString stringWithUTF8String:CACHE_PATH];
  if (useCache) {
    NSDictionary *attrs = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:nil];
    NSDate *modDate = attrs[NSFileModificationDate];
    if (modDate && [[NSDate date] timeIntervalSinceDate:modDate] < CACHE_VALIDITY) {
      NSString *token = [NSString stringWithContentsOfFile:path encoding:NSUTF8StringEncoding error:nil];
      if (token.length > 0) return [token stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    }
  }

  NSString *freshToken = fetchBearerToken();
  if (useCache) {
    [freshToken writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
  return freshToken;
}

void printHelp() {
  printf("Usage:\n");
  printf("  FetchTranscript <podcastId> [--cache-bearer-token]\n\n");
  printf("Options:\n");
  printf("  --cache-bearer-token   Use cached Bearer token if valid for 30 days, reducing the number of requests\n");
  printf("  --help                 Show this help message\n");
}

int main(int argc, const char * argv[]) {
  @autoreleasepool {
    // Handle the help dialog
    if (argc < 2 || strcmp(argv[1], "--help") == 0) {
      printHelp();
      return 0;
    }

    // Get the podcast ID that we're trying to download
    NSString *podcastId = [NSString stringWithUTF8String:argv[1]];
    BOOL useCache = NO;
    if (argc >= 3 && strcmp(argv[2], "--cache-bearer-token") == 0) {
      useCache = YES;
    }

    NSString *bearer = getBearerToken(useCache);
    if (!bearer || bearer.length < 10) {
      NSLog(@"Failed to obtain Bearer token");
      return 1;
    }

    // Download the TTML file
    NSString *transcriptURLStr = [NSString stringWithFormat:@"https://amp-api.podcasts.apple.com/v1/catalog/us/podcast-episodes/%@/transcripts?fields=ttmlToken,ttmlAssetUrls&include%%5Bpodcast-episodes%%5D=podcast&l=en-US&with=entitlements", podcastId];
    NSMutableURLRequest *transcriptRequest = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:transcriptURLStr]];
    [transcriptRequest setValue:[NSString stringWithFormat:@"Bearer %@", bearer] forHTTPHeaderField:@"Authorization"];

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);

    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:transcriptRequest completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) { 
      NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
      
      NSDictionary *attrs = json[@"data"][0][@"attributes"];
      NSString *ttmlURL = attrs[@"ttmlAssetUrls"][@"ttml"];
      NSString *ttmlPath = [attrs[@"ttmlToken"] componentsSeparatedByString:@"/"].lastObject;

      NSData *ttmlData = [NSData dataWithContentsOfURL:[NSURL URLWithString:ttmlURL]];
      if (![ttmlData writeToFile:ttmlPath atomically:YES]) {
        NSLog(@"Failed to save %@", ttmlPath);
      }

      dispatch_semaphore_signal(sema);
    }];
    [task resume];

    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);
  }
  return 0;
}