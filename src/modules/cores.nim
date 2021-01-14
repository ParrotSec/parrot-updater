import strutils
import osproc


var userChoice*: bool


iterator readTextLines(data: string): TaintedString =
  var txt: string
  for chr in data:
    if chr != '\n':
      txt &= chr
    else:
      yield txt
      txt = ""


proc fileNameToURL*(fileName: string): string =
  #[
    Convert index file name to URL of Repo
    For example: vietnam.deb.parrot.sh_parrot_dists_rolling-testing_InRelease
    -> 
  ]#
  return "https://" & fileName.split("/")[^1].replace("_", "/")


proc urlToIndexFile*(url, edition: string): string =
  #[
    Convert URL in source list to file name that will be saved at $localRepoIndex
    Return release file that was saved in system
  ]#

  return url.split("://")[1].replace("/", "_") & "_dists_" & edition & "_InRelease"


proc urlToRepoURL*(url, edition: string): string =
  #[
    Convert URL in source list repo URL
    Return full URL that contains Release file
  ]#
  return url & "/dists/" & edition & "/InRelease"


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


proc getUpgradeablePackages*(): int =
  #[
    Get all packages that wasn't upgraded by apt
  ]#
  let
    cmd = "apt list --upgradeable"
    output = execProcess(cmd)
  return count(output, "/")
