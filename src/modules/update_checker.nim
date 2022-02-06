import os
import cores
import strutils
import httpclient


proc getHTTPData*(url: string): string =
  #[
    Read Release file on server
  ]#
  var client = newHttpClient()
  let resp = client.get(url)
  return resp.body


proc doCheckUpdateForLines(line, arch: string): RepoIndex =
  var sourceInfo: RepoIndex
  sourceInfo.arch = arch
  aptSourceToFile(sourceInfo, line)
  aptSourceToURL(sourceInfo, line)

  if sourceInfo.indexFileErr:
    return sourceInfo
  try:
    if parseDateFromFile(sourceInfo.indexFile) != parseDateFromText(getHTTPData(sourceInfo.repoUrl)):
      sourceInfo.hasUpdate = true
    else:
      echo "Up to date ", sourceInfo.repoUrl
      sourceInfo.hasUpdate = false
    return sourceInfo
  except:
    sourceInfo.runtimeErr = true
    echo "Runtime error ", sourceInfo.repoUrl
    return sourceInfo


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
  
  for line in lines(sourceListFile):
    if line.startsWith("deb "):
      let repoInfo = doCheckUpdateForLines(line, debArch)
      if repoInfo.indexFileErr:
        updateStatus.cacheErr += 1
      elif repoInfo.runtimeErr:
        updateStatus.runtimeErr += 1
      elif repoInfo.isParrotRepo == true:
        if repoInfo.hasUpdate:
          updateStatus.parrotUpdate += 1
      else:
        if repoInfo.hasUpdate:
          updateStatus.sideUpdate += 1

  for kind, path in walkDir(sourceListDir):
    if path.endsWith(".list"):
      for line in lines(path):
        if line.startsWith("deb "):
          let repoInfo = doCheckUpdateForLines(line, debArch)
          if repoInfo.indexFileErr:
            updateStatus.cacheErr += 1
          elif repoInfo.runtimeErr:
            updateStatus.runtimeErr += 1
          elif repoInfo.isParrotRepo == true:
            if repoInfo.hasUpdate:
              updateStatus.parrotUpdate += 1
          else:
            if repoInfo.hasUpdate:
              updateStatus.sideUpdate += 1

  return updateStatus
