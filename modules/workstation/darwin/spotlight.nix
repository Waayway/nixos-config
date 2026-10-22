{ hostPlatform, lib, ... }:
{
  # Spotlight: only apps, calculator, developer sources and system settings.
  # `orderedItems` is the classic category list; EnabledPreferenceRules and
  # DisabledUTTypes are the macOS 26+ sources/file-type switches.
  config = lib.optionalAttrs hostPlatform.isDarwin {
    system.defaults.CustomUserPreferences = {
      "com.apple.Spotlight" = {
        orderedItems = [
          {
            name = "APPLICATIONS";
            enabled = true;
          }
          {
            name = "MENU_EXPRESSION";
            enabled = true;
          }
          {
            name = "CONTACT";
            enabled = false;
          }
          {
            name = "MENU_CONVERSION";
            enabled = false;
          }
          {
            name = "MENU_DEFINITION";
            enabled = false;
          }
          {
            name = "SOURCE";
            enabled = true;
          }
          {
            name = "DOCUMENTS";
            enabled = false;
          }
          {
            name = "EVENT_TODO";
            enabled = false;
          }
          {
            name = "DIRECTORIES";
            enabled = false;
          }
          {
            name = "FONTS";
            enabled = false;
          }
          {
            name = "IMAGES";
            enabled = false;
          }
          {
            name = "MESSAGES";
            enabled = false;
          }
          {
            name = "MOVIES";
            enabled = false;
          }
          {
            name = "MUSIC";
            enabled = false;
          }
          {
            name = "MENU_OTHER";
            enabled = false;
          }
          {
            name = "PDF";
            enabled = false;
          }
          {
            name = "PRESENTATIONS";
            enabled = false;
          }
          {
            name = "MENU_SPOTLIGHT_SUGGESTIONS";
            enabled = false;
          }
          {
            name = "SPREADSHEETS";
            enabled = false;
          }
          {
            name = "SYSTEM_PREFS";
            enabled = true;
          }
          {
            name = "TIPS";
            enabled = false;
          }
          {
            name = "BOOKMARKS";
            enabled = false;
          }
        ];
        EnabledPreferenceRules = [
          "Custom.relatedContents"
          "System.folders"
          "Domain.IMAGES"
          "Domain.MOVIES"
          "Domain.MUSIC"
          "Domain.PDF"
          "Domain.SPREADSHEETS"
          "FileProvider.com.google.drivefs.fpext/gdrive-110120237501209960764"
          "com.apple.AppStore"
          "com.apple.iBooksX"
          "com.apple.iCal"
          "com.apple.AddressBook"
          "com.apple.Dictionary"
          "com.google.drivefs"
          "com.apple.mail"
          "com.microsoft.Excel"
          "com.microsoft.Outlook"
          "com.microsoft.Powerpoint"
          "com.microsoft.Word"
          "com.apple.Notes"
          "com.microsoft.OneDrive"
          "com.apple.Photos"
          "com.apple.podcasts"
          "com.apple.reminders"
          "com.apple.Safari"
          "com.apple.shortcuts"
          "com.apple.tips"
          "com.apple.VoiceMemos"
        ];
        DisabledUTTypes = [
          "com.adobe.pdf"
          "com.apple.iwork.numbers.numbers"
          "com.apple.iwork.numbers.sffnumbers"
          "com.apple.iwork.numbers.template"
          "com.apple.localized-pdf-bundle"
          "com.apple.protected-mpeg-4-audio"
          "com.apple.quicktime-movie"
          "com.microsoft.excel.sheet.binary.macroenabled"
          "com.microsoft.excel.xls"
          "org.openxmlformats.spreadsheetml.sheet"
          "org.openxmlformats.spreadsheetml.sheet.macroenabled"
          "public.3gpp"
          "public.3gpp2"
          "public.audio"
          "public.image"
          "public.movie"
          "public.mpeg"
          "public.mpeg-4"
          "public.mpeg-4-audio"
          "public.mpeg-video"
          "public.spreadsheet"
        ];
      };
    };
  };
}
