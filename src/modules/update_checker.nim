import os
import cores
import strutils
import httpclient


proc getHTTPData*(url: string): HTTPData =
  #[
    Read Release file on server
  ]#
  var
    client = newHttpClient()
    statusCheck: HTTPData
  let
    resp = client.get(url)
  echo "[-] ", resp.status, " ", url
  if not resp.status.startsWith("200 OK"):
    statusCheck.isErr = true
  else:
    statusCheck.isErr = false
    statusCheck.body = resp.body
  return statusCheck


proc doCheckUpdateForLines(line, arch: string): RepoIndex =
  var sourceInfo: RepoIndex
  sourceInfo.arch = arch
  aptSourceToFile(sourceInfo, line)
  aptSourceToURL(sourceInfo, line)

  if sourceInfo.indexFileErr:
    return sourceInfo
  try:
    # If HTTP status code != 200, return error and don't do date comparison
    let checkRepoUpdate = getHTTPData(sourceInfo.repoUrl)
    if checkRepoUpdate.isErr:
      sourceInfo.runtimeErr = true
      return sourceInfo

    if parseDateFromFile(sourceInfo.indexFile) != parseDateFromText(checkRepoUpdate.body):
      sourceInfo.hasUpdate = true
      echo "[!] New update is available ", sourceInfo.repoUrl
    else:
      echo "[*] Up to date ", sourceInfo.repoUrl
      sourceInfo.hasUpdate = false
    return sourceInfo
  except:
    sourceInfo.runtimeErr = true
    echo "Runtime error ", sourceInfo.repoUrl
    return sourceInfo


proc get_source_status(pkgStatus: var UpdateStatus, sourcePath, debArch: string) =
  for line in lines(sourcePath):
    if line.startsWith("deb "):
      let repoInfo = doCheckUpdateForLines(line, debArch)
      if repoInfo.isParrotRepo:
        pkgStatus.parrotBranches += 1
        if repoInfo.hasUpdate:
          pkgStatus.parrotOutdated += 1
        elif repoInfo.runtimeErr:
          pkgStatus.parrotRuntimeErr += 1
        elif repoInfo.indexFileErr:
          pkgStatus.parrotFileErr += 1
      else:
        if repoInfo.hasUpdate:
          pkgStatus.sideOutdated += 1
        elif repoInfo.runtimeErr:
          pkgStatus.sideRuntimeErr += 1
        elif repoInfo.indexFileErr:
          pkgStatus.sideFileErr += 1


proc do_check_source_list*(): UpdateStatus =
  const
    sourceListFile = "/etc/apt/sources.list"
    sourceListDir = "/etc/apt/sources.list.d"
  let
    debArch = getDebArch()
  var
    updateStatus = UpdateStatus(
      parrotOutdated: 0,
      parrotRuntimeErr: 0,
      parrotFileErr: 0,
      sideOutdated: 0,
      sideRuntimeErr: 0,
      sideFileErr: 0,
      upgradable: 0,
      parrotBranches: 0,
    )

  get_source_status(updateStatus, sourceListFile, debArch)

  for kind, path in walkDir(sourceListDir):
    if path.endsWith(".list") and kind == pcFile:
      get_source_status(updateStatus, path, debArch)

  return updateStatus
