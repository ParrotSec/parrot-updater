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
      if repoInfo.indexFileErr:
        pkgStatus.cacheErr += 1
      elif repoInfo.runtimeErr:
        pkgStatus.runtimeErr += 1
      elif repoInfo.isParrotRepo == true:
        if repoInfo.hasUpdate:
          pkgStatus.parrotUpdate += 1
      else:
        if repoInfo.hasUpdate:
          pkgStatus.sideUpdate += 1


proc do_check_source_list*(): UpdateStatus =
  const
    sourceListFile = "/etc/apt/sources.list"
    sourceListDir = "/etc/apt/sources.list.d"
  let
    debArch = getDebArch()
  var
    updateStatus = UpdateStatus(
      parrotUpdate: 0,
      sideUpdate: 0,
      upgradable: 0,
      runtimeErr: 0,
      cacheErr: 0,
    )
  # TODO when user change repository, there are index files are not downloaded
  # however, the result still shows up to date. Think about this

  get_source_status(updateStatus, sourceListFile, debArch)

  for kind, path in walkDir(sourceListDir):
    if path.endsWith(".list") and kind == pcFile:
      get_source_status(updateStatus, path, debArch)

  return updateStatus
