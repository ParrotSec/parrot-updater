import strutils
import gintro / [gtk, gobject, glib, notify, vte]
import modules / [cores, update_checker]
import os

var countUpgrade: NeedUpgrade


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


proc checkUpdate*(): int =
  let updateResult = do_check_source_list()
  if updateResult.parrotOutdated > 0:
    handleNotify("New updates are available", "Parrot OS has new update" , 2)
    return 1
  elif updateResult.parrotFileErr > 0:
    handleNotify("Your system needs upgrading", "No index files found" , 2)
    return 1
  elif updateResult.parrotRuntimeErr > 0:
    handleNotify("Error while checking update", "Runtime error" , 2)
    return 1
  elif updateResult.sideOutdated > 0:
    handleNotify("New updates are available", intToStr(updateResult.sideOutdated) & " updates from 3rd-party repositories" , 1)
    return 1
  # Skip missing index files for 3rd party repos. URL might not supported
  elif updateResult.sideRuntimeErr > 0:
    handleNotify("Error while checking update", "Runtime error" , 1)
    return 1
  else:
    countUpgrade = getUpgradeablePackages()
    if countUpgrade.pkgCount > 0:
      handleNotify("Upgrades are required", intToStr(countUpgrade.pkgCount) & " package[s] are not upgraded", 1)
    else:
      handleNotify("Your system is up to date", "", 0)


proc onExit(w: Window) =
  #[
    Close program by click on title bar
  ]#
  mainQuit()


proc onUpdateCompleted(v: Terminal, signal: int) =
  var quit = true
  if signal == 0:
    handleNotify("Parrot Updater", "Your system is upgraded", 0)
  elif signal == 256:
    handleNotify("Parrot Updater", "Authentication error: Wrong password", 2)
  elif signal == 9 or signal == 2:
    # When user cancel upgrade (using apt) by press control + C, signal is 2
    handleNotify("Parrot Updater", "Cancelled by user", 1)
    quit = true
  else:
    handleNotify("Parrot Updater", "Error while running parrot-upgrade", 2)
    quit = false
  if quit:
    mainQuit()


proc upgradeCallback(terminal: ptr Terminal00; pid: int32; error: ptr glib.Error; userData: pointer) {.cdecl.} =
  discard


proc startUpgrade() =
  #[
    Spawn a native GTK terminal
  ]#
  let
    boxUpgrade = newBox(Orientation.vertical, 3)
    vteUpgrade = newTerminal()
  
  boxUpgrade.packStart(vteUpgrade, true, true, 3)
  vteUpgrade.connect("child-exited", onUpdateCompleted)
  vteUpgrade.spawnAsync(
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
  let upgradeDialog = newWindow()
  upgradeDialog.setTitle("Parrot Upgrade")
  upgradeDialog.setPosition(WindowPosition.center)
  upgradeDialog.add(boxUpgrade)
  upgradeDialog.connect("destroy", onExit)

  upgradeDialog.showAll()
  gtk.main()


proc onClickUpgrade(b: Button, d: Dialog) =
  d.destroy()
  userChoice = true
  startUpgrade()


proc onClickDontUpgrade(b: Button, d: Dialog) =
  userChoice = false
  d.destroy()


proc showUpgradable(b: Button) =
  #[
    Show all upgradeble packages from `apt list --upgradable` in a new dialog
  ]#
  let
    retDialog = newDialog()
    areaDialog = getContentArea(retDialog)
    listPkg = newTextView()
    listPkgBuffer = getBuffer(listPkg)
    scrollWindow = newScrolledWindow()
  
  listPkg.setEditable(false)
  listPkg.setCursorVisible(false)

  listPkgbuffer.setText(cstring(countUpgrade.pkgList), len(countUpgrade.pkgList))

  scrollWindow.add(listPkg)
  areaDialog.add(scrollWindow)

  retDialog.title = "Upgradable packages"
  retDialog.setResizable(false)
  retDialog.showAll()
  retDialog.setDefaultSize(300, -1)
  discard retDialog.run()
  retDialog.destroy()


proc askUpgradePopup() =
  #[
    Ask user do they want to update
  ]#
  let
    retDialog = newDialog()
    bDialog = getContentArea(retDialog)
    labelAsk = newLabel("Do you want to upgrade your system?")
    boxButtons = newBox(Orientation.horizontal, 3)
    btnY = newButton("Yes")
    btnN = newButton("No")
    btnView = newButton("Show upgradable")
  
  btnY.connect("clicked", onClickUpgrade, retDialog)
  btnN.connect("clicked", onClickDontUpgrade, retDialog)
  btnY.grabFocus()
  boxButtons.packEnd(btnN, false, false, 3)
  boxButtons.packStart(btnY, false, false, 3)

  if countUpgrade.pkgCount != 0:
    btnView.connect("clicked", showUpgradable)
    boxbuttons.packStart(btnView, true, true, 3)

  retDialog.title = "System upgrade"
  retDialog.setResizable(false)

  bDialog.packStart(labelAsk, true, true, 3)
  bDialog.packEnd(boxButtons, true, true, 3)
  retDialog.showAll()
  discard retDialog.run()
  retDialog.destroy()


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
    userChoice = false
    let updateResult = checkUpdate()
    if updateResult != 0:
      askUpgradePopup()


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
        askUpgradePopup()
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
