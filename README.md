# DESCRIPTION / OVERVIEW

This is the simplest, possibly dumbest, iOS automated build script possible.

It reads in a json config file either from `stdin` or the first shell argument and then pulls from git, updates common dependencies, builds, archives, validates, tags, and uploads to Apple - in any combination of those taks. If you set the script to run via cron or launchd, it can start a build process any time it detects new commits.

For my personal projects, I rarely find the need for automated builds. But whenever I'm working on a team at a company or with a client, I do genuinely find it useful to have a reproducable build system that can verify builds and also submit to App Store Connect.

In the past I've used awful frankenstein Jenkins servers, Xcode bots, Microsoft App Center, Bitrise, etc. They all have their plus and minuses. But I typically prefer something simpler that I can tweak to my needs and easily adopt to work with small businesses (my preferred type of employer) and freelance clients - many of whom don't want me sending their source code to be built on 3rd party servers.

So this script is the result of me taking a few days to cobble together a clean version of the many, various build scripts I've written over the years. It's certainly not perfect, nor does it do everything. But, it is simple to read, understand, and extend. And, most importantly, it meets *my* needs.

**Caveats:** I'm not an `xcodebuild` expert. I don't claim this script will handle your hand-crafted, artisinal Xcode workspace/project. But it should handle most common scenarios and be tweakable for the rest.

Also, while I do know my way around a shell pretty well, I'm by no means a pro. So those of you who are more exprienced with bash scripting will likely look at a lot of the commmands and approaches below and laugh. (Especically around my complete lack of knowledge about variable expansion!) And that's OK. Feedback is welcome! Pull requests are especially welcome and appreciated!

# INSTRUCTIONS

This script can be executed in two ways:

1. `/path/to/builder /path/to/project/builder.json`

2. `cat builder.json | /path/to/builder`

In either situation, builder.json contains a single JSON dictionary that configures how the script behaves. Here's a sample...

```
{
  "project_name" : "Your App",
  "workspace_path" : "$HOME/src/path-to-project/App.xcworkspace",
  "scheme" : "Scheme Name",
  "git_branch" : "release/testflight",
  "increment_build" : false,
  "clean" : true,
  "delete_derived_data" : false,
  "pod_install" : false,
  "carthage_update" : false,
  "build" : true,
  "export" : true,
  "validate" : true,
  "submit" : true,
  "tag_release" : true,
  "slack_webhook" : "https://hooks.slack.com/services/XXXXXXXX/YYYYYYYYY/ZZZZZZZZZZZZZZZZZ",
  "force_run" : false
}
```

When you run the script, it will clear away any uncommitted work, pull down the latest changes, and if any new ones are detected, begin the build process.

**NOTE:** If no new changes are detected, the script will immedaitely exit. However, you can override this behavior and force the script to run by including a `force` argument like this...

`/path/to/builder /path/to/projects/builder.json force`

Or by setting `force_run` to true in the JSON config file or via stdin.

**NOTE:** Because this script will do a `git --reset hard`, if you set it up to run automatically, it should probably be done on a dedicated build machine or in a separate cloned repo that isn't your primary working directory.

**REQUIREMENT:** This script depends on the [jq](https://stedolan.github.io/jq/) command being installed. See the "STUFF YOU NEED TO CONFIGURE" section below for more information.

**REQUIREMENT:** Inside the folder that your `.xcworkspace` is contained within, you need to create `ExportOptions.plist`. This file is used to configure the code signing settings used when exporting your build. Take a look at the sample included in this repo. You can find the values you need to configure in the `.plist` (such as Team ID and Provisioning Profile name) from App Store Connect.

**REQUIREMENT:** Because this script communicates with Apple to validate and submit your builds, you need to supply it with your Apple ID and password. It would be a very-bad, no-good choice to hard code those credentials in this script. Instead, you can either store them in variables that will be sourced from `$HOME/.pw` (not exactly secure, but whatever) or via the `APPLE_ID` and `APPLE_PASSWORD` environment variables. Bascically, what I want to say is I take no responsibility for how securely or insecurely you store those credentials and hand them off to this script. Just be careful and do whatever you think is best for your situation.

Also, if you run this script via cron or launchd, your `login.keychain` will be locked, which means codesign won't be able to read your signing certificates and private keys. This script will attempt to unlock your keychain automatically if you set the `KEYCHAIN_PW` environment variable either in `$HOME/.pw` or by some other means.

**OPTIONAL:** Speaking of launchd, that's my preferred way of running this script automatically since it is much more customizable than cron and generally works better with macOS.

Take a look at `sample.builder.launchd.plist` in this repo. You can install that .plist into your launchd jobs and it will run the build script `launchd-builder.sh` every minute (as long as another build isn't currently happening). Inside `launchd-builder.sh`, just add a list of builder commands you want to run as shown in the example file included in this repo.

To install the launchd .plist:

1. Copy `sample.builder.launchd.plist` to `~/Library/LaunchAgents`
2. Run `launchctl load ~/Library/LaunchAgents/sample.builder.launchd.plist`
3. Run `launchctl start /Library/LaunchAgents/sample.builder.launchd.plist`

Or, you can cough up a few bucks and use the wonderful [LaunchControl](https://www.soma-zone.com/LaunchControl/) app by [soma-zone](https://www.soma-zone.com) to configure everything for you.

**OPTIONAL:** You can supply the URL to a Slack webhook in `builder.json`'s `slack_webhook` property and the script will notify you of build progress there. If you omit the webhook URL, the script will just pipe status messages to stdout as usual.

**INFO:** After running the script, log files from the various commands' `stdout` and `stderr` as well as the build's `.xcarchive` and `.ipa` are stored inside this script's folder in the hidden `.logs` and `.archives` directories. When run, the script will echo the path to the log files directory in case you want to `tail -f` and follow along with the build progress. (I would like to add a `--verbose` option at some point that echoes ALL of the various build tasks output to stdout so it's easier to follow. But that's for another day...)
	
Anyway, like I said, I don't claim this script is perfectly robust, foolproof, or the best choice for every situation. But it meets my needs, and hopefully you'll find it useful, too!

Feel free to send questions / feedback to [rth@tyler.io](mailto:rth@tyler.io). And you can also report bugs and submit pull requests on [GitHub](https://github.com/tylerhall/builder).