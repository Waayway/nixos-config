# The people of the household, declared once; every host sets the same value so any
# configuration can validate `homelab.access.*.members` against it.
{
  homelab.people = {
    thijs = {
      displayName = "Thijs";
      email = "thijs@vanwaaij.com";
      admin = true;
    };
    arie = {
      displayName = "Arie";
      email = "arie@vanwaaij.com";
    };
  };
}
