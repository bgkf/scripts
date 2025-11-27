### Get File Alias ###

A means to get the file path of the original file that an alias poits to.

Two methods to check if the file is an alias (and not a link).<br>
```
% 
% file /Applications/Adobe\ InDesign\ 2025/Uninstall\ Adobe\ InDesign\ 2025 
/Applications/Adobe InDesign 2025/Uninstall Adobe InDesign 2025: MacOS Alias file
% 
% 
% mdls -name kMDItemKind /Applications/Adobe\ InDesign\ 2025/Uninstall\ Adobe\ InDesign\ 2025 
kMDItemKind = "Alias"
% 
```

Script to get the file path of the orignal (where the alias points to).<br>
```
#! /bin/bash

swift -e '
import Foundation
let path = CommandLine.arguments[1]
let url = URL(fileURLWithPath: path)
do {
    let data = try URL.bookmarkData(withContentsOf: url)
    var isStale = false
    let orig = try URL(resolvingBookmarkData: data, bookmarkDataIsStale: &isStale)
    print(orig.path)
} catch {
    print("Error: \(error.localizedDescription)")
}
' "/Applications/Adobe Illustrator 2024/Uninstall Illustrator 2024"
```

