import strutils
#https://wiki.debian.org/DebianRepository/Format


proc aptSourceToURL*(line: string): string =
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
  
  if splitedLine[startPos].endsWith("/parrot"):
    return splitedLine[startPos] & "/dists/" & splitedLine[startPos + 1] & "/InRelease"
  else:
    # TODO support $(arch)
    result = splitedLine[startPos]
    if not result.endsWith("/"):
      result &= "/"
    result &= splitedLine[startPos + 1] & "InRelease"
    if "$(ARCH)" in result:
      echo "Unsupported format $(ARCH) for line ", line

# doAssert aptSourceToURL("deb https://vietnam.deb.parrot.sh/parrot rolling-testing main contrib non-free") == "https://vietnam.deb.parrot.sh/parrot/dists/rolling-testing/InRelease"
# doAssert aptSourceToURL("deb https://download.sublimetext.com/ apt/stable/") == "https://download.sublimetext.com/apt/stable/InRelease"
# doAssert aptSourceToURL("deb https://download.sysdig.com/stable/deb stable-$(ARCH)/") == "https://download.sysdig.com/stable/deb/stable-amd64/InRelease"

proc aptSourceToFile*(line: string): string =
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
  
  result = splitedLine[startPos].split("://")[1].replace("/", "_")
  if result.endsWith("_parrot"):
    result &= "_dists_" & splitedLine[startPos + 1] & "_InRelease"
  else:  
    # TODO support $(arch)
    # if not result.endsWith("/"):
    #   result &= "/"
    result &= splitedLine[startPos + 1].replace("/", "_") & "InRelease"
    if "$(ARCH)" in result:
      echo "Unsupported format $(ARCH) for line ", line
  return "/var/lib/apt/lists/" & result

# doAssert aptSourceToFile("deb https://vietnam.deb.parrot.sh/parrot rolling-testing main contrib non-free") == "/var/lib/apt/lists/vietnam.deb.parrot.sh_parrot_dists_rolling-testing_InRelease"
# doAssert aptSourceToFile("deb https://download.sublimetext.com/ apt/stable/") == "/var/lib/apt/lists/download.sublimetext.com_apt_stable_InRelease"
# doAssert aptSourceToFile("deb https://download.sysdig.com/stable/deb stable-$(ARCH)/") == "/var/lib/apt/lists/download.sysdig.com_stable_deb_stable-amd64_InRelease"