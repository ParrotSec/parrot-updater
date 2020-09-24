import strutils
import httpclient
import os
import gintro / [gtk, gobject, glib, notify, vte]

type
  Mirror = object
    url: string
    edition: string

var userChoice*: bool

const
  repoConfig = "/etc/apt/sources.list.d/parrot.list"
  localRepoIndex = "/var/lib/apt/lists/"

iterator readTextLines(data: string): TaintedString =
  var txt: string
  for chr in data:
    if chr != '\n':
      txt &= chr
    else:
      yield txt
      txt = ""


proc fileNameToURL(fileName: string): string =
  #[
    Convert index file name to URL of Repo
    For example: vietnam.deb.parrot.sh_parrot_dists_rolling-testing_InRelease
    -> 
  ]#
  return "https://" & fileName.split("/")[^1].replace("_", "/")


proc urlToFileName(url, edition: string): string =
  #[
    Convert URL in source list to file name that will be saved at $localRepoIndex
    Return release file that was saved in system
  ]#
  let info = url.split("/")
  return info[2] & "_" & info[3] & "_dists_" & edition & "_InRelease"


proc urlToRepoURL(url, edition: string): string =
  #[
    Convert URL in source list repo URL
    Return full URL that contains Release file
  ]#
  return url & "/dists/" & edition & "/InRelease"


proc updateServerChange(url: string): string =
  #[
    Read Release file on server
  ]#
  var client = newHttpClient()
  let resp = client.get(url)
  return resp.body


proc parseDateFromFile(filePath: string): string =
  #[
    Get Value of Date section in Index file
  ]#
  for line in lines(filePath):
    if line.startsWith("Date: "):
      return line


proc parseDateFromText(data: string): string =
  #[
    Get Value of Date section from server HTTP return
  ]#
  for line in readTextLines(data):
    if line.startsWith("Date: "):
      return line


proc sendNotify(sumary, body, icon: string) =
  #[
    Display IP when user click on CheckIP button
    Show the information in system's notification
  ]#

  discard init("Parrot Updater")
  let ipNotify = newNotification(sumary, body, icon)
  discard ipNotify.show()


proc onExit(w: Window) =
  #[
    Close program by click on title bar
  ]#
  mainQuit()


proc checkUpdate(): int =
  var
    numOutOfDated = 0
    numErrors = 0
    checked = 0
    mirrorIndexes: seq[string]
    cdnIndexes: seq[string]
  
  # Check all local index files
  for kind, path in walkDir(localRepoindex):
    if kind == pcFile and path.endsWith("InRelease"):
      let mirrorIndex = path.split("/")[^1]
      if mirrorIndex.startsWith("deb.parrot.sh") or mirrorIndex.startsWith("deb.parrotsec.org"):
        cdnIndexes.add(path)
      else:
        mirrorIndexes.add(path)

  # If there is no index
  if len(mirrorIndexes) == 0 and len(cdnIndexes) == 0:
    # numErrors += 1
    echo "[x] Local file is missing"
    sendNotify("Your system hasn't been updated", "Run parrot-upgrade for latest patches", "security-low")
    return -1
  else:
    for line in lines(repoConfig):
      # Check for binary only. skip deb-src
      if line.startsWith("deb "):
        let
          info = line.split(" ")
        var
          mirror = Mirror(
            url: info[1],
            edition: info[2]
          )
        echo "[i] Checking [" & mirror.url & "] [" & mirror.edition & "]"
        checked += 1
        # If system is using cdn, we try using mirror url
        if mirror.url.startsWith("https://deb.parrot.sh") or mirror.url.startsWith("https://deb.parrotsec.org") or mirror.url.startsWith("https://mirror.parrot.sh"):
          var
            localDate: string
            serverDate: string
          # Check if system doesn't have mirror index, we use main url
          # FIXME only use first result in file list. Need to do more complex check
          # What if multiple url, and duplicate?
          if len(mirrorIndexes) == 0:
            localDate = parseDateFromFile(cdnIndexes[0])
            serverDate = parseDateFromText(updateServerChange(urlToRepoURL(mirror.url, mirror.edition)))
          # We have mirror. Do the check with mirror URL on server
          else:
            localDate = parseDateFromFile(mirrorIndexes[0])
            # let newMirrorURL = fileNameToURL(mirrorIndexes[0])
            mirror.url = fileNameToURL(mirrorIndexes[0])
            echo "[i] Switch to mirror " & mirror.url
            serverDate = parseDateFromText(updateServerChange(mirror.url))
          if localDate != serverDate:
            echo "[!] New update is available on " & mirror.edition
            echo "[+] Your last update: " & localDate
            echo "[+] Repo last update: " & serverDate
            sendNotify("New update is available on " & mirror.edition, "Server " & serverDate & "\nMachine " & localDate, "security-low")
            numOutOfDated += 1
        # Else (mirror url directly), we check update directly
        else:
          if len(mirrorIndexes) == 0:
            echo "[x] Missing index of " & mirror.url
            sendNotify("Parrot update", "Index for current mirror is missing", "security-low")
            numErrors += 1
            # numOutOfDated = -1
          else:
            let
              fileFromURL = localRepoIndex & urlToFileName(mirror.url, mirror.edition)
            if fileExists(fileFromURL):
              let
                localDate = parseDateFromFile(fileFromURL)
                serverDate = parseDateFromText(updateServerChange(urlToRepoURL(mirror.url, mirror.edition)))
              if localDate != serverDate:
                echo "[!] New update is available on " & mirror.edition
                echo "[+] Your last update: " & localDate
                echo "[+] Repo last update: " & serverDate
                sendNotify("New update is available on " & mirror.edition, "Server " & serverDate & "\nMachine " & localDate, "security-low")
                numOutOfDated += 1
            else:
              echo "[x] Missing index of " & mirror.url
              numErrors += 1
    # Complete for loop. Get the result
    if numOutOfDated > 0:
      echo "[!] Your system need to update"
      sendNotify("New update is available", "Run command \"sudo parrot-upgrade\" to upgrade your system", "security-medium")
    elif numOutOfDated == 0:
      if numErrors == 0:
        echo "[*] Your system is up to date"
        sendNotify("Parrot Updater", "Your system is up to date", "security-high")
      else:
        # If 1 or more mirror doens't have error, we still count (old unused mirror?)
        if checked < numErrors:
          echo "[!] Error while checking for update"
          echo "[*] Your system is up to date"
          sendNotify("Parrot Updater", "Your system is up to date", "security-high")
        # If all mirrors has error, return error
        else:
          echo "[x] Error while checking for update"
          sendNotify("Parrot Updater", "Your system hasn't been updated on new mirror", "security-low")
          return -1
    return numOutOfDated


proc onUpdateCompleted(v: Terminal, signal: int) =
  if signal == 0:
    echo "[*] Update completed"
    sendNotify("Parrot Updater", "Your system is upgraded", "security-high")
  elif signal == 256:
    sendNotify("Parrot Updater", "Authentication error: Wrong password", "security-low")
    echo "[x] Authentication error: Wrong password"
  elif signal == 9:
    sendNotify("Parrot Updater", "Cancelled by user", "security-low")
    echo "[x] Cancelled by user"
  else:
    sendNotify("Parrot Updater", "Error while running parrot-upgrade", "security-low")
    echo "[x] Failed to update"
  mainQuit()


proc startUpgrade() =
  #[
    Spawn a native GTK terminal and run nyx with it to show current tor status
  ]#
  # TODO try exit after completed
  let
    upgradeDialog = newWindow()
    boxUpgrade = newBox(Orientation.vertical, 3)
    doUpgrade = newTerminal()
  
  boxUpgrade.add(doUpgrade)

  upgradeDialog.setTitle("Parrot Upgrade")
  upgradeDialog.setPosition(WindowPosition.center)
  doUpgrade.connect("child-exited", onUpdateCompleted)
  doUpgrade.spawnAsync(
    {noLastlog}, # pty flags
    nil, # working directory
    ["/usr/bin/sudo", "/usr/bin/parrot-upgrade"], # args
    # ["/usr/bin/echo", "/usr/bin/parrot-upgrade"],
    [], # envv
    {doNotReapChild}, # spawn flag
    nil, # Child setup
    nil, # child setup data
    nil, # chlid setup data destroy
    -1, # timeout
    nil, # cancellabel
    nil, # callback
    nil, # pointer
  )
  upgradeDialog.add(boxUpgrade)
  upgradeDialog.connect("destroy", onExit)

  upgradeDialog.showAll()
  gtk.main()


proc onClickUpgrade(b: Button, d: Dialog) =
  # d.destroy()
  userChoice = true
  # sendNotify("Parrot Upgrade", "Completed", "security-high")


proc onClickDontUpgrade(b: Button, d: Dialog) =
  userChoice = false
  # d.destroy()


proc askUpgradePopup(): Dialog =
  #[
    Ask user do they want to update
  ]#
  let
    retDialog = newDialog()
    bDialog = getContentArea(retDialog)
    labelAsk = newLabel("Do you want to upgrade?")
    btnY = newButton("Yes")
    btnN = newButton("No")
  
  btnY.connect("clicked", onClickUpgrade, retDialog)
  btnN.connect("clicked", onClickDontUpgrade, retDialog)
  btnY.grabFocus()
  retDialog.addActionWidget(btnY, 1)
  retDialog.addActionWidget(btnN, 0)
  retDialog.title = "System upgrade"

  bDialog.add(labelAsk)
  retDialog.showAll()
  return retDialog


proc onClickUpdate(b: Button, d: Dialog) =
  # d.destroy()
  sendNotify("Parrot Update", "Start checking for update", "security-medium")
  userChoice = true



proc onClickDontUpdate(b: Button, d: Dialog) =
  # d.destroy()
  userChoice = false


proc askUpdatePopup(): Dialog =
  #[
    Ask user do they want to update
  ]#
  let
    retDialog = newDialog()
    bDialog = getContentArea(retDialog)
    labelAsk = newLabel("Do you want to update?")
    btnY = newButton("Yes")
    btnN = newButton("No")
  
  btnY.connect("clicked", onClickUpdate, retDialog)
  btnN.connect("clicked", onClickDontUpdate, retDialog)
  btnY.grabFocus()
  # retDialog.setIconName("minupdate-checking")
  retDialog.addActionWidget(btnY, 1)
  retDialog.addActionWidget(btnN, 0)
  retDialog.title = "Check update"

  bDialog.add(labelAsk)
  retDialog.showAll()
  return retDialog


proc startUpdate(w: Window) =
  let
    updateDialog = askUpdatePopup()

  discard updateDialog.run()
  updateDialog.destroy()
  if userChoice:
    let updateResult = checkUpdate()
    if updateResult != 0:
      let upgrade = askUpgradePopup()
      discard upgrade.run()
      upgrade.destroy()
      if userChoice:
        startUpgrade()


proc main() =
  #[
    Create new window
  ]#
  gtk.init()

  let
    mainBoard = newWindow()
  
  mainBoard.title = "Parrot Updater"
  mainBoard.position = WindowPosition.center

  mainBoard.setBorderWidth(3)
  # Start doing as user's parameters
  # Put it here to fix crash when calling pop up
  if paramCount() == 1:
    if paramStr(1) == "--check-only":
      # Only compare index file and quit
      discard checkUpdate()
    elif paramStr(1) == "--force":
      # Skip asking and start parrot-upgrade
      startUpgrade()
    elif paramStr(1) == "--auto":
      # Skip asking user and do update based on result
      let updateResult = checkUpdate()
      if updateResult != 0:
        startUpgrade()
    elif paramStr(1) == "--fast":
      # Skip ask user for check update.
      let updateResult = checkUpdate()
      if updateResult != 0:
        let upgrade = askUpgradePopup()
        discard upgrade.run()
        upgrade.destroy()
        if userChoice:
          startUpgrade()
  else:
    startUpdate(mainBoard)

  mainBoard.connect("destroy", onExit)

main()
