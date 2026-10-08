// Adds the given folders to the end of the Finder sidebar "Favorites" if they
// exist and aren't there yet. Never removes or reorders existing items.
// Usage: swift finder-sidebar.swift [--remove] <path>...
import CoreServices
import Foundation

let args = Array(CommandLine.arguments.dropFirst())
let remove = args.first == "--remove"
let paths = remove ? Array(args.dropFirst()) : args

let list = LSSharedFileListCreate(nil, kLSSharedFileListFavoriteItems.takeUnretainedValue(), nil)!
  .takeRetainedValue()

func items() -> [LSSharedFileListItem] {
  var seed: UInt32 = 0
  return LSSharedFileListCopySnapshot(list, &seed)!.takeRetainedValue() as! [LSSharedFileListItem]
}

func path(of item: LSSharedFileListItem) -> String? {
  guard let url = LSSharedFileListItemCopyResolvedURL(item, 0, nil)?.takeRetainedValue() as URL?
  else { return nil }
  return url.resolvingSymlinksInPath().path
}

for raw in paths {
  let url = URL(fileURLWithPath: raw).resolvingSymlinksInPath()
  let existing = items().first { path(of: $0) == url.path }
  if remove {
    if let item = existing { LSSharedFileListItemRemove(list, item); print("removed \(url.path)") }
    continue
  }
  guard existing == nil else { continue }
  guard FileManager.default.fileExists(atPath: url.path) else {
    print("skip (missing) \(url.path)")
    continue
  }
  // kLSSharedFileListItemLast is a sentinel pointer Swift can't retain, so
  // insert after the current last item (Favorites is never empty on macOS).
  guard let last = items().last else { continue }
  LSSharedFileListInsertItemURL(list, last, nil, nil, url as CFURL, nil, nil)
  print("added \(url.path)")
}
