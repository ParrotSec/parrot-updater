import strutils
import os
import osproc
# https://wiki.debian.org/DebianRepository/Format

type
  RepoIndex* = object
    repoUrl*: string
    indexFile*: string
    isParrotRepo*: bool
    hasUpdate*: bool
    indexFileErr*: bool
    runtimeErr*: bool
    arch*: string
  UpdateStatus* = object
    parrotUpdate*: int
    sideUpdate*: int
    upgradable*: int
    runtimeErr*: int
    cacheErr*: int
  NeedUpgrade* = object
    pkgList*: string
    pkgCount*: int
  HTTPData* = object
    isErr*: bool
    body*: string

var userChoice*: bool


iterator readTextLines(data: string): string =
  var txt: string
  for chr in data:
    if chr != '\n':
      txt &= chr
    else:
      yield txt
      txt = ""


proc getIsDesktop*(): bool =
  if isEmptyOrWhitespace(getEnv("XDG_CURRENT_DESKTOP")):
    return false
  return true


proc getDebArch*(): string =
  #[
    Execute command `dpkg-architecture -l`
    Parse section DEB_HOST_ARCH= and return
  ]#
  let
    cmd = "dpkg-architecture -l"
    output = execProcess(cmd)
  for line in readTextLines(output):
    if line.startsWith("DEB_HOST_ARCH"):
      return line.split("=")[1]


proc getUpgradeablePackages*(): NeedUpgrade =
  #[
    Get all packages that wasn't upgraded by apt
    # TODO this command is slow and uses a lot of memory (74 mb)
    Try better code
  ]#
  let
    cmd = "apt list --upgradeable"
    output = execProcess(cmd)
  var
    count = 0
    pkg = ""
  for line in readTextLines(output):
    if "/" in line:
      count += 1
      pkg &= line & "\n"
  
  result.pkgList = pkg
  result.pkgCount = count


proc parseDateFromFile*(filePath: string): string =
  #[
    Get Value of Date section in Index file
  ]#
  for line in lines(filePath):
    if line.startsWith("Date: "):
      return line


proc parseDateFromText*(data: string): string =
  #[
    Get Value of Date section from server HTTP return
  ]#
  for line in readTextLines(data):
    if line.startsWith("Date: "):
      return line


proc aptSourceToURL*(repo: var RepoIndex, line: string) =
  #[
    Convert source in apt to URL on repository
    Return full URL that contains InRelease file
    Example: deb https://vietnam.deb.parrot.sh/parrot rolling-testing main contrib non-free
    Return: https://vietnam.deb.parrot.sh/parrot/dists/rolling-testing/InRelease
    deb https://download.sublimetext.com/ apt/stable/
    -> https://download.sublimetext.com/apt/stable/InRelease
    deb https://download.sysdig.com/stable/deb stable-$(ARCH)/
    -> https://download.sysdig.com/stable/deb/stable-amd64/InRelease
  ]#
  let splitedLine = line.split(" ")
  #[
    if line has no [arch]:
      splitedLine[2] = URL
      splitedLine[3] = branch
      splitedLine[4 .. ^] = components
  ]#
  var startPos = 1
  if "[" in line:
    startPos = 2
  
  repo.repoUrl = splitedLine[startPos]
  if repo.repoUrl.endsWith("/parrot"):
    repo.isParrotRepo = true

  # Has components, add "/dists/"
  if len(splitedLine) - 2 - startPos > 0:
    repo.repoUrl &= "/dists/"
  elif not repo.repoUrl.endsWith("/"):
    repo.repoUrl &= "/"
  
  repo.repoUrl &= splitedLine[startPos + 1]

  if not repo.repoUrl.endsWith("/"):
    repo.repoUrl &= "/InRelease"
  else:
    repo.repoUrl &= "InRelease"

  if "$(ARCH)" in repo.repoUrl:
    repo.repoUrl = repo.repoUrl.replace("$(ARCH)", repo.arch)

# doAssert aptSourceToURL("deb https://vietnam.deb.parrot.sh/parrot rolling-testing main contrib non-free") == "https://vietnam.deb.parrot.sh/parrot/dists/rolling-testing/InRelease"
# doAssert aptSourceToURL("deb https://download.sublimetext.com/ apt/stable/") == "https://download.sublimetext.com/apt/stable/InRelease"
# doAssert aptSourceToURL("deb https://download.sysdig.com/stable/deb stable-$(ARCH)/") == "https://download.sysdig.com/stable/deb/stable-amd64/InRelease"


proc aptSourceToFile*(repo: var RepoIndex, line: string) =
  #[
    Convert source in apt to file name in /var/lib/apt/lists
    Return full absolute path of the file
    Example: deb https://vietnam.deb.parrot.sh/parrot rolling-testing main contrib non-free
    Return: /var/lib/apt/lists/vietnam.deb.parrot.sh_parrot_dists_rolling-testing_InRelease
    deb https://download.sublimetext.com/ apt/stable/
    -> /var/lib/apt/lists/download.sublimetext.com_apt_stable_InRelease
    deb https://download.sysdig.com/stable/deb stable-$(ARCH)/
    -> /var/lib/apt/lists/download.sysdig.com_stable_deb_stable-amd64_InRelease
  ]#
  let splitedLine = line.split(" ")
  #[
    if line has no [arch]:
      splitedLine[2] = URL
      splitedLine[3] = branch
      splitedLine[4 .. ^] = components
  ]#
  var startPos = 1
  if "[" in line:
    startPos = 2
  
  # Remove protocol
  repo.indexFile = splitedLine[startPos].split("://")[1].replace("/", "_")

  if repo.indexFile.endsWith("_parrot"):
    repo.isParrotRepo = true

  # Has components, add "_dists_"
  if len(splitedLine) - 2 - startPos > 0:
    repo.indexFile &= "_dists_"
  elif not repo.indexFile.endsWith("_"):
    repo.indexFile &= "_"
  repo.indexFile &= splitedLine[startPos + 1].replace("/", "_")

  if not repo.indexFile.endsWith("_"):
    repo.indexFile &= "_InRelease"
  else:
    repo.indexFile &= "InRelease"
  
  if "$(ARCH)" in repo.indexFile:
    repo.indexFile = repo.indexFile.replace("$(ARCH)", repo.arch)

  repo.indexFile = "/var/lib/apt/lists/" & repo.indexFile

  if not fileExists(repo.indexFile):
    echo "[x] File not found ", repo.indexFile
    repo.indexFileErr = true
  else:
    echo "[-] Found ", repo.indexFile
    repo.indexFileErr = false
  

# doAssert aptSourceToFile("deb https://vietnam.deb.parrot.sh/parrot rolling-testing main contrib non-free") == "/var/lib/apt/lists/vietnam.deb.parrot.sh_parrot_dists_rolling-testing_InRelease"
# doAssert aptSourceToFile("deb https://download.sublimetext.com/ apt/stable/") == "/var/lib/apt/lists/download.sublimetext.com_apt_stable_InRelease"
# doAssert aptSourceToFile("deb https://download.sysdig.com/stable/deb stable-$(ARCH)/") == "/var/lib/apt/lists/download.sysdig.com_stable_deb_stable-amd64_InRelease"

let isDesktop* = getIsDesktop()
