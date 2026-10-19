# The people of the household, declared once; every host sets the same value so any
# configuration can validate `homelab.access.*.members` against it.
{
  homelab.people = {
    thijs = {
      displayName = "Thijs van Waaij";
      email = "thijs@vanwaaij.com";
      admin = true;
    };
  };
}
