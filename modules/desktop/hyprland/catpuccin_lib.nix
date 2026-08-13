lib:
let
  colorConf = builtins.readFile ./catpuccin.conf;
  lines = lib.strings.splitString "\n" colorConf;

  lineToAttrDef =
    line:
    let
      trimmedLine = lib.strings.trim line;
    in
    if trimmedLine == "" || lib.strings.hasPrefix "#" trimmedLine then
      { }
    else
      let
        parts = lib.strings.splitString " = " trimmedLine;
      in
      if builtins.length parts == 2 then
        let
          keyString = lib.strings.trim (builtins.elemAt parts 0);
          valueString = lib.strings.trim (builtins.elemAt parts 1);
        in
        lib.attrsets.genAttrs [ keyString ] (_: valueString)
      else
        { };

  catpuccinConfig = lib.attrsets.zipAttrs (lib.lists.forEach lines lineToAttrDef);
in
catpuccinConfig
