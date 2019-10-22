#!/bin/bash

# ###########################
# DESCRIPTION / OVERVIEW
# ###########################

# This is the simplest, possibly dumbest, iOS automated build script possible.

# It reads in a json config file either from stdin or the first shell argument and then pulls from git, updates common
# dependencies, builds, archives, validates, tags, and uploads to Apple - in any combination of those taks. If you set the
# script to run via cron or launchd, it can start a build process any time it detects new commits.

# For my personal projects, I rarely find the need for automated builds. But whenever I'm working on a team at a company
# or with a clients, I do genuinely find it useful to have a reproducable build system that can verify builds and also
# submit to App Store Connect.

# In the past I've used awful frankenstein Jenkins servers, Xcode bots, Microsoft App Center, Bitrise, etc.
# They all have their plus and minuses. But I typically prefer something simpler that I can tweak to my needs
# and easily adopt to work with small businesses (my preferred type of employer) and freelance clients.

# So this script is the result of me taking a few days to cobble together a clean version of the many, various
# build scripts I've written over the years. It's certainly not perfect, nor does it do everything. But, it is
# simple to read, understand, and extend. And, most importantly, it meets *my* needs.

# Caveats: I'm not an xcodebuild expert. I don't claim this script will handle your hand-crafted, artisinal Xcode workspace/project.
# But it should handle most common scenarios and be tweakable for the rest.

# Also, while I do know my way around a shell pretty well, I'm by no means a pro. So those of you who are more
# exprienced with bash scripting will likely look at a lot of the commmands and approaches below and laugh. (Especically around
# my complete lack of knowledge about variable expansion!) And that's OK. Feedback is welcome! Pull requests are especially
# welcome and appreciated!

# ###########################
# INSTRUCTIONS
# ###########################

# This script can be executed in two ways:

# 1. /path/to/builder /path/to/projects/builder.json

# 2. cat builder.json | /path/to/builder

# In either situation, builder.json contains a single JSON dictionary that configures how the script behaves. Here's
# a sample...

# {
#   "project_name" : "Your App",
#   "workspace_path" : "App.xcworkspace",
#   "scheme" : "Scheme Name",
#   "git_branch" : "release/testflight",
#   "increment_build" : false,
#   "clean" : true,
#   "delete_derived_data" : false,
#   "pod_install" : false,
#   "carthage_update" : false,
#   "build" : true,
#   "export" : true,
#   "validate" : true,
#   "submit" : true,
#   "tag_release" : true,
#   "slack_webhook" : "https://hooks.slack.com/services/XXXXXXXX/YYYYYYYYY/ZZZZZZZZZZZZZZZZZ",
#   "force_run" : false,
#   "post_command" : "/path/to/some/script"
# }

# When you run the script, if you specify a GIT_BRANCH to checkout, it will clear away any uncommitted work, pull
# down the latest changes, and if any new ones are detected, begin the build process.

# If GIT_BRANCH is not specified or is an empty string, the repo will be used in whatever current state it is in.

# NOTE: If no new changes are detected, the script will immedaitely exit. However, you can override this
# behavior and force the script to run by including a "force" argument like this...

# /path/to/builder /path/to/projects/builder.json force

# Or by setting "force_run" to true in the JSON config file or via stdin.

# It is assumed that WORKSPACE_PATH is the filename of an .xcworkspace inside the same directory that builder.json is in.

# NOTE: Because this script will do a git --reset hard, if you set it up to run automatically, it should
# probably be done on a dedicated build machine or in a separate cloned repo that isn't your primary
# working directory.

# REQUIREMENT: This script depends on the jq command being installed. See the "STUFF YOU NEED TO CONFIGURE" section
# below for more information.

# REQUIREMENT: Inside the folder that your .xcworkspace is contained within, you need to create ExportOptions.plist.
# This file is used to configure the code signing settings used when exporting your build. Take a look at the sample
# included in this repo. You can find the values you need to configure in the .plist (such as Team ID and Provisioning
# Profile name) from App Store Connect.

# REQUIREMENT: Because this script communicates with Apple to validate and submit your builds, you need to supply it
# with your Apple ID and password. It would be a very-bad, no-good choice to hard code those credentials in this
# script. Instead, you can either store them in variables that will be sourced from $HOME/.pw (not exactly secure,
# but whatever) or via the APPLE_ID and APPLE_PASSWORD environment variables. Bascically, what I want to say is I take
# no responsibility for how securely or insecurely you store those credentials and hand them off to this script. Just
# be careful and do whatever you think is best for your situation.

# Also, if you run this script via cron or launchd, your login.keychain will be locked, which means codesign won't be
# able to read your signing certificates and private keys. This script will attempt to unlock your keychain automatically
# if you set the KEYCHAIN_PW environment variable either in $HOME/.pw or by some other means.

# OPTIONAL: Speaking of launchd, that's my preferred way of running this script automatically since it is much more
# customizable than cron and generally works better with macOS.

# Take a look at sample.builder.launchd.plist in this repo. You can install that .plist into your launchd jobs and it
# will run the build script launchd-builder.sh every minute (as long as another build isn't currently happening.)
# Inside launchd-builder.sh, just add a list of builder commands you want to run as shown in the example file.

# To install the launchd .plist:

# 1. Copy sample.builder.launchd.plist to ~/Library/LaunchAgents
# 2. Run "launchctl load ~/Library/LaunchAgents/sample.builder.launchd.plist"
# 3. Run "launchctl start /Library/LaunchAgents/sample.builder.launchd.plist"

# Or, you can cough up a few bucks and use the wonderful LaunchControl app by soma-zone...
# https://www.soma-zone.com/LaunchControl/ to configure everything for you.

# OPTIONAL: You can supply the URL to a Slack webhook in builder.json's slack_webhook property and the script will
# notify you of build progress there. If you omit the webhook URL, the script will just pipe status messages to stdout
# as usual.

# INFO: After running the script, log files from the various commands' stdout and stderr as well as the build's
# .xcarchive and .ipa are stored inside this script's folder in the hidden ".logs" and ".archives" directories.
# When run, the script will echo the path to the log files directory in case you want to `tail -f` and follow along
# with the build progress. (I would like to add a --verbose option at some point that echoes ALL of the various build
# tasks output to stdout so it's easier to follow. But that's for another day...)

# Anyway, like I said, I don't claim this script is perfectly robust, foolproof, or the best choice for every situation.
# But it meets my needs, and hopefully you'll find it useful, too!

# Feel free to send questions / feedback to rth@tyler.io. And you can also report bugs and submit pull requests on GitHub.

# ###########################
# STUFF YOU NEED TO CONFIGURE
# ###########################

# This script requires jq be installed: https://stedolan.github.io/jq/
# The easiest way to do that is to install homebrew: https://brew.sh
# And then run "brew install jq"
JQ_PATH="/usr/local/bin/jq"

CARTHAGE_PATH="/usr/local/bin/carthage"
COCOAPODS_PATH="/usr/local/bin/pod"

# ###########################
# HELPER FUNCTIONS
# ###########################

# Print a successful log message and optionally send to a Slack channel.
# $1 = Message
log_message() {
    echo ""
    echo "### $1"
    echo ""
    if [[ "$SLACK_WEBHOOK" =~ .*slack.* ]]; then
        echo $1 > "$BUILDER_PATH/.text"
        $JQ_PATH -n --rawfile message "$BUILDER_PATH/.text" '{"text":$message}' > "$BUILDER_PATH/.json"
        curl -s -d @"$BUILDER_PATH/.json" -H "Content-Type: application/json" -X POST "$SLACK_WEBHOOK" > /dev/null
        rm "$BUILDER_PATH/.text"
        rm "$BUILDER_PATH/.json"
    fi
}

# Print a failure log message and optionally send to a Slack channel along with a log and error log file as attachments.
# $1 = Message
# $2 = Log filename
# $3 = Error log filename
log_failure() {
    echo ""
    echo "ERROR: $1"
    echo ""
    if [[ "$SLACK_WEBHOOK" =~ .*slack.* ]]; then
        curl -s -d "{'text':'*ERROR:* $1'}" -H "Content-Type: application/json" -X POST "$SLACK_WEBHOOK" > /dev/null
        slack_log "Log: $1" $2
        slack_log "Error Log: $1" $3
    fi
}

# Post the contents of a text file (log file) to a Slack channel as an attachment.
# $1 = Message
# $2 = Text filename to attach
slack_log() {
    if [ -s $2 ]; then
        echo "\`\`\`" > "$BUILDER_PATH/.text"
        cat $2 >> "$BUILDER_PATH/.text"
        echo "\`\`\`" >> "$BUILDER_PATH/.text"

        TS=`date +%s`

        $JQ_PATH -n --arg title "$1" --rawfile text "$BUILDER_PATH/.text" --arg ts $TS '{"attachments":[{"fallback":$title,"color":"#ff0000","title":$title,"text":$text,"ts":$ts}]}' > "$BUILDER_PATH/.json"

        curl -d @"$BUILDER_PATH/.json" -H "Content-Type: application/json" -X POST "$SLACK_WEBHOOK"

        rm "$BUILDER_PATH/.text"
        rm "$BUILDER_PATH/.json"
    fi
}

# ###########################
# TASKS
# ###########################

update_git() {
    # Only update with git if a branch is specified. This gives us the option to NOT specify
    # a branch, which allows us to build using whatever branch and dirty state the repo
    # happens to be in.
    if [ "$GIT_BRANCH" != "" ] && [ "$GIT_BRANCH" != "null" ]; then
        # log_message "Resetting to most recent commit on $GIT_BRANCH"
        git -C "$SRC_PATH" reset --hard
        git -C "$SRC_PATH" fetch --all
        git -C "$SRC_PATH" checkout $GIT_BRANCH
        git -C "$SRC_PATH" pull
    fi
}

# This function immediately ends the script execution if no new commits are found - unless FORCE_RUN == true.
check_for_new_commits() {
    CURRENT_HASH=`git -C "$SRC_PATH" rev-parse HEAD`
    if [ -f "$LAST_COMMIT_PATH" ]; then
        if [[ $(< $LAST_COMMIT_PATH) == "$CURRENT_HASH" ]]; then
            echo "No changes found for $PROJECT_NAME."
            # You _could_ post this message to Slack, etc. each time, but that would probably get noisy if this script is run frequently.
            # log_message "No changes found."
            if [ "$1" == "force" ]; then
                echo "Continuing with rest of script..."
            else
                if [ $FORCE_RUN == "true" ]; then
                    echo "Continuing with rest of script..."
                else
                    exit 0
                fi
            fi
        fi
    fi
}

# Increments the project's build number and commits the change to git.
increment_build_number() {
    if [ $INCREMENT_BUILD == "true" ]; then
        log_message "Incrementing build version..."

        cd "$SRC_PATH"
        agvtool next-version -all
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Could not increment build version."
            exit 1
        fi

        log_message "Committing and pushing new build version..."
        NEW_VERSION=`agvtool what-version -terse`
        git -C "$SRC_PATH" commit -am "Incrementing build verison to $NEW_VERSION."
        git -C "$SRC_PATH" push
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Failed to push new build version"
            exit 1
        fi
    fi
}

# Stores the current git hash into a file so we can use it to test for new commits the next time the script is run.
save_latest_commit_hash() {
    git -C "$SRC_PATH" rev-parse HEAD > "$LAST_COMMIT_PATH"
}

unlock_keychain() {
    # Unlock the macOS keychain so Xcode's CLI tools have access to our signing certificates and keys...
    # Unfortunately, Xcode only allows reading certificates from the user's personal keychain (at least as far I can figure out).
    # That means if this script were run via cron or some other non-interactive shell, we'd have to
    # hardcode our personal macOS password to unlock the keychain. For privacy's sake, we don't want
    # to do this (obviously). Instead, (while not the most secure solution), save your password into a
    # file at ~/.pw and we'll read it in as needed.
    #
    # Obviously, this isn't the most secure solution, but it works for me. Feel free modify
    # this to use your own secrets management solution.

    log_message "Unlocking keychain..."

    source $HOME/.pw
    security unlock-keychain -p $KEYCHAIN_PW ~/Library/Keychains/login.keychain
    RESULT=$?
    if [ $RESULT -ne 0 ]; then
        log_failure "Could not unlock keychain."
        exit 1
    fi
}

clean_workspace() {
    if [ $CLEAN == "true" ]; then
        log_message "Cleaning..."
        xcodebuild clean -workspace "$WORKSPACE_PATH" -scheme $SCHEME
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Clean failed."
            exit 1
        fi
    fi
}

delete_derived_data() {
    if [ $DELETE_DERIVED_DATA == "true" ]; then
        log_message "Deleting derived data..."
        rm -rf $HOME/Library/Developer/Xcode/DerivedData
    fi
}

pod_install() {
    if [ $POD_INSTALL == "true" ]; then
        log_message "Installing Cocoapods..."
        $COCOAPODS_PATH install --project-directory="$SRC_PATH" > "$LOG_PATH/pod.log" 2> "$LOG_PATH/pod-error.log"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Cocoapods install failed." "$LOG_PATH/pod.log" "$LOG_PATH/pod-error.log"
            exit 1
        fi
    fi
}

carthage_update() {
    if [ $CARTHAGE_UPDATE == "true" ]; then
        log_message "Updating Carthage..."
        $CARTHAGE_PATH update --project-directory "$SRC_PATH" > "$LOG_PATH/carthage.log" 2> "$LOG_PATH/carthage-error.log"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Carthage update failed." "$LOG_PATH/carthage.log" "$LOG_PATH/carthage-error.log"
            exit 1
        fi
    fi
}

build_for_archiving() {
    if [ $BUILD == "true" ]; then
        log_message "Building..."
        xcodebuild -workspace "$WORKSPACE_PATH" -scheme $SCHEME -destination "generic/platform=iOS"  archive -archivePath "$ARCHIVE_PATH/App" > "$LOG_PATH/build.log" 2> "$LOG_PATH/build-error.log"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Build failed." "$LOG_PATH/build.log" "$LOG_PATH/build-error.log"
            exit 1
        fi
    fi
}

export_build() {
    if [ $EXPORT == "true" ]; then
        log_message "Exporting archive."
        xcodebuild -exportArchive -archivePath "$ARCHIVE_PATH/App.xcarchive" -exportPath "$ARCHIVE_PATH" -exportOptionsPlist "$SRC_PATH/ExportOptions.plist" > "$LOG_PATH/archive.log"  2> "$LOG_PATH/archive-error.log"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Export archive failed." "$LOG_PATH/archive.log" "$LOG_PATH/archive-error.log"
            exit 1
        fi
    fi
}

validate_app() {
    if [ $VALIDATE == "true" ]; then
        log_message "Validating..."
        altool --validate-app -f "$ARCHIVE_PATH/$SCHEME.ipa" -u "$APPLE_ID" -p "$APPLE_PASSWORD" > "$LOG_PATH/validate.log"  2> "$LOG_PATH/validate-error.log"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Validation failed." "$LOG_PATH/validate.log" "$LOG_PATH/validate-error.log"
            exit 1
        fi
    fi
}

submit_app() {
    if [ $SUBMIT == "true" ]; then
        log_message "Submitting to Apple..."
        altool --upload-app -f "$ARCHIVE_PATH/$SCHEME.ipa" -u "$APPLE_ID" -p "$APPLE_PASSWORD" > "$LOG_PATH/submit.log"  2> "$LOG_PATH/submit-error.log"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Upload to App Store Connect failed." "$LOG_PATH/submit.log" "$LOG_PATH/submit-error.log"
            exit 1
        fi
    fi
}

# Creates a git tag of the format "v<BuildNumber>" and pushes it to origin.
tag_release() {
    if [ $TAG_RELEASE == "true" ]; then
        cd "$SRC_PATH"
        CURRENT_VERSION=`agvtool what-version -terse`

        log_message "Tagging release v$CURRENT_VERSION..."

        git -C "$SRC_PATH" tag "v$CURRENT_VERSION"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Could not create tag v$CURRENT_VERSION."
            exit 1
        fi

        log_message "Pushing new tag..."
        git -C "$SRC_PATH" push origin "v$CURRENT_VERSION"
        RESULT=$?
        if [ $RESULT -ne 0 ]; then
            log_failure "Could not push new tag."
            exit 1
        fi
    fi
}

# Runs a command after everything else has finished.
run_post_command() {
    if [ -f "$POST_COMMAND" ]; then
		log_message "Running post command $POST_COMMAND"
		$POST_COMMAND
	fi
}

# ###########################
# LOAD OUR SETTINGS FROM either builder.json or stdin
# ###########################

if [ ! "$1" == "" ]; then
    if [ ! -f "$1" ]; then
        log_failure "$1 does not exist"
        exit 1
    fi
    CONFIG=`cat "$1"`
	JSON_DIR=`dirname "$1"`
else
    log_message "Reading config from stdin..."
    CONFIG=`cat`
fi

BUILDER_PATH=`dirname $0`

echo $CONFIG > "$BUILDER_PATH/.config"

PROJECT_NAME=`$JQ_PATH -r '.project_name' "$BUILDER_PATH/.config"`
SCHEME=`$JQ_PATH -r '.scheme' "$BUILDER_PATH/.config"`
GIT_BRANCH=`$JQ_PATH -r '.git_branch' "$BUILDER_PATH/.config"`
INCREMENT_BUILD=`$JQ_PATH -r '.increment_build' "$BUILDER_PATH/.config"`
CLEAN=`$JQ_PATH -r '.clean' "$BUILDER_PATH/.config"`
POD_INSTALL=`$JQ_PATH -r '.pod_install' "$BUILDER_PATH/.config"`
CARTHAGE_UPDATE=`$JQ_PATH -r '.carthage_update' "$BUILDER_PATH/.config"`
BUILD=`$JQ_PATH -r '.build' "$BUILDER_PATH/.config"`
EXPORT=`$JQ_PATH -r '.export' "$BUILDER_PATH/.config"`
VALIDATE=`$JQ_PATH -r '.validate' "$BUILDER_PATH/.config"`
SUBMIT=`$JQ_PATH -r '.submit' "$BUILDER_PATH/.config"`
SLACK_WEBHOOK=`$JQ_PATH -r '.slack_webhook' "$BUILDER_PATH/.config"`
TAG_RELEASE=`$JQ_PATH -r '.tag_release' "$BUILDER_PATH/.config"`
DELETE_DERIVED_DATA=`$JQ_PATH -r '.delete_derived_data' "$BUILDER_PATH/.config"`
FORCE_RUN=`$JQ_PATH -r '.force_run' "$BUILDER_PATH/.config"`
POST_COMMAND=`$JQ_PATH -r '.post_command' "$BUILDER_PATH/.config"`

WORKSPACE_PATH=`$JQ_PATH -r '.workspace_path' "$BUILDER_PATH/.config"`
WORKSPACE_PATH="$JSON_DIR/$WORKSPACE_PATH"

rm "$BUILDER_PATH/.config"

# ###########################
# COMPUTE ANY ADDITIONAL SETTINGS WE NEED
# ###########################

SRC_PATH=`dirname "$WORKSPACE_PATH"`

HASH=`echo $PROJECT_NAME $GIT_BRANCH | md5`
LAST_COMMIT_PATH="$BUILDER_PATH/.last_commits/$HASH"
ARCHIVE_PATH="$BUILDER_PATH/.archives/$HASH"
LOG_PATH="$BUILDER_PATH/.logs/$HASH"
NOW=`date`
START_TS=`date +%s`

# ###########################
# ADDITIONAL HELPER STUFF
# ###########################

export PATH="/Applications/Xcode.app/Contents/Developer/usr/bin/:$PATH" # Puts altool in our $PATH.
source $HOME/.pw # Our App Store Connect and keychain credentials are stored in here.

# ###########################
# GENERAL SETUP
# ###########################

mkdir -p $BUILDER_PATH/.last_commits
mkdir -p $BUILDER_PATH/.archives
mkdir -p $LOG_PATH

# Remove archives older than 30 days.
find "$BUILDER_PATH/.archives" -type d -mtime +30 -delete

# ###########################
# LET'S DO THIS!
# ###########################

echo ""
echo "###########################"
echo ""
echo "Beginning build process for $PROJECT_NAME..."
echo "Located at $WORKSPACE_PATH"
echo "Using branch $GIT_BRANCH"
echo "Logs will be stored in $LOG_PATH"
echo ""
echo "###########################"
echo ""

update_git
check_for_new_commits $2
log_message "*$NOW*: Found new *$PROJECT_NAME* changes. Beginning build..."
increment_build_number
save_latest_commit_hash
unlock_keychain
clean_workspace
pod_install
carthage_update
build_for_archiving
export_build
validate_app
submit_app
tag_release
run_post_command

# ###########################
# SUCCESS!
# ###########################

END_TS=`date +%s`
TOTAL_SECS=$(expr $END_TS - $START_TS)
RUN_TIME=`printf '%dh:%dm:%ds\n' $(($TOTAL_SECS/3600)) $(($TOTAL_SECS%3600/60)) $(($TOTAL_SECS%60))`

log_message "*Success!* 🎉🥳"
log_message "Total Time: $RUN_TIME"

exit 0