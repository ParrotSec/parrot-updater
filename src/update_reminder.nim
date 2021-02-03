import strutils
import httpclient
import os
import gintro / [gtk, gobject, glib, notify, vte]
import modules / cores

let isDesktop = if getEnv("XDG_CURRENT_DESKTOP") == "": false else: true
var
  mainRepoCount = 0
  mainRepoHasUpdate = 0
  mainRepoHasError = 0
  mainRepoIndexNotFound = 0
  otherRepoCount = 0
  otherRepoHasUpdate = 0
  otherRepoHasError = 0
  otherRepoIndexNotFound = 0


proc updateServerChange*(url: string): string =
  #[
    Read Release file on server
  ]#
  var client = newHttpClient()
  let resp = client.get(url)
  return resp.body


proc sendNotify(sumary, body, icon: string) =
  #[
    Display IP when user click on CheckIP button
    Show the information in system's notification
  ]#

  discard init("Parrot Updater")
  let ipNotify = newNotification(sumary, body, icon)
  discard ipNotify.show()


proc handleNotify(title, msg: string, lvl = 0) =
  #[
    Display message on terminal or prompt notification
    Level: what type do we use?
      0: good. Notification: security high
      1: not good. Notification: security medium
      2: bad. Notification: security low
  ]#
  if not isDesktop:
    # TODO color for terminal
    let cli_msg = "[" & title & "] [" & msg & "]"
    if lvl == 0:
      echo "[*] " & cli_msg
    elif lvl == 1:
      echo "[!] " & cli_msg
    else:
      echo "[x] " & cli_msg
  else:
    if lvl == 0:
      sendNotify(title, msg, "security-high")
    elif lvl == 1:
      sendNotify(title, msg, "security-medium")
    else:
      sendNotify(title, msg, "security-low")


proc onExit(w: Window) =
  #[
    Close program by click on title bar
  ]#
  mainQuit()


proc handleSourceList(path: string) =
  #[
    Parse line to get information of mirror
    Debian format `deb [arch] url distribution component1 component2 component3`
    arch is optional
  ]#
  let isParrotRepo = if path.split("/")[^1] == "parrot.list": true else: false
  if isParrotRepo:
    mainRepoCount += 1
  else:
    otherRepoCount += 1

  for line in lines(path):
    try:
      if line.startsWith("deb "):
        let elements = line.split(" ")
        var
          indexPath = "/var/lib/apt/lists/"
          url, distribution: string
        if elements[1].startsWith("http"):
          #[
            No arch found. We have format `deb url distro components...`
            We pass URL and distro to generate index file.
          ]#
          url = elements[1]
          distribution = elements[2]
        else:
          url = elements[2]
          distribution = elements[3]
        
        indexPath &= urlToIndexFile(url, distribution)

        if not fileExists(indexPath):
          # We found no index file in /var/lib/apt/lists/
          # Return error here
          if isParrotRepo:
            mainRepoIndexNotFound += 1
          else:
            otherRepoIndexNotFound += 1
        else:
          # Everything is good. We get Date section from file
          let
            localDate = parseDateFromFile(indexPath)
            serverDate = parseDateFromText(updateServerChange(urlToRepoURL(url, distribution)))
          if localDate != serverDate:
            # Return code of has update
            if isParrotRepo:
              mainRepoHasUpdate += 1
            else:
              otherRepoHasUpdate += 1
          else:
            # No update
            discard
    except:
      if isParrotRepo:
        mainRepoHasError += 1
      else:
        otherRepoHasError += 1


proc checkUpdate(): int =
  let pathSourceList = "/etc/apt/sources.list.d/"
  for kind, path in walkDir(pathSourceList):
    handleSourceList(path)
  
  if mainRepoCount == 0 and otherRepoCount == 0:
    handleNotify("Sources list error", "No source list found")
    return -1
  else:
    if mainRepoHasUpdate > 0:
      handleNotify("Parrot OS has new update", "" , 2)
      return 1
    elif otherRepoHasUpdate > 0:
      handleNotify("Other vendor updates are available", intToStr(otherRepoHasUpdate) & " / " & intToStr(otherRepoCount) & " of third-party has new update" , 1)
      return 1
    else:
      if mainRepoIndexNotFound > 0:
        handleNotify("Your system hasn't been upgraded", "Upgrade now for latest security patches", 2)
        return 1
      elif otherRepoIndexNotFound > 0:
        # Maybe have a bug for weird index file
        handleNotify("Other vendor updates are required", intToStr(otherRepoIndexNotFound) & " / " & intToStr(otherRepoCount) & " of third-party hasn't upgraded", 1)
        return 1
      elif mainRepoHasError > 0:
        handleNotify("Error while checking for update", "Error while checking update for Parrot", 2)
        return 1
      elif otherRepoHasError > 0:
        handleNotify("Error while checking for update", "Error while checking update for other vendors", 2)
        return 1
      else:
        let needUpgradePackages = getUpgradeablePackages()
        if needUpgradePackages == 0:
          handleNotify("Your system is up to date", "", 0)
        else:
          handleNotify("Upgrades are required", intToStr(needUpgradePackages) & " package[s] are not upgraded", 1)
        return needUpgradePackages


proc onUpdateCompleted(v: Terminal, signal: int) =
  if signal == 0:
    handleNotify("Parrot Updater", "Your system is upgraded", 0)
  elif signal == 256:
    handleNotify("Parrot Updater", "Authentication error: Wrong password", 2)
  elif signal == 9:
    # FIX me: app shows 2 times
    handleNotify("Parrot Updater", "Cancelled by user", 1)
  else:
    handleNotify("Parrot Updater", "Error while running parrot-upgrade", 2)
  mainQuit()


proc upgradeCallback(terminal: ptr Terminal00; pid: int32; error: ptr glib.Error; userData: pointer) {.cdecl.} =
  discard


proc startUpgrade() =
  #[
    Spawn a native GTK terminal and run nyx with it to show current tor status
  ]#
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
    [], # envv
    {}, # spawn flag
    nil, # Child setup
    nil, # child setup data
    nil, # chlid setup data destroy
    -1, # timeout
    nil, # cancellabel
    upgradeCallback, # callback
    nil, # pointer
  )
  upgradeDialog.packStart(boxUpgrade, true, true, 3)
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
  sendNotify("Parrot Update", "Start checking for updates", "security-high")
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
    labelAsk = newLabel("Do you want to check for new updates?")
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


proc gtkUpdateCheck() =
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
    # elif paramStr(1) == "--force":
    #   # Skip asking and start parrot-upgrade
    #   startUpgrade()
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
    elif paramStr(1) == "scheduled":
      # Ask user before start apt
      startUpdate(mainBoard)
  else:
    startUpdate(mainBoard)

  mainBoard.connect("destroy", onExit)

if isDesktop:
  gtkUpdateCheck()
else:
  let updateResult = checkUpdate()
  if updateResult != 0:
    startUpgrade()
