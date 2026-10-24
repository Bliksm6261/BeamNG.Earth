"""region.py (the edition's playable region; the mod's region.lua reads the same polygons, regiondata.lua)."""
import os
import re
import sys
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), ".."))
import region  # noqa: E402

LUA = os.path.join(region.ROOT, "mod", "beamng_earth", "lua", "ge", "extensions", "beamngEarth", "regiondata.lua")


class RegionTest(unittest.TestCase):
    def tearDown(self):
        region.set_data()

    def test_the_countries_and_their_neighbours(self):
        self.assertTrue(region.enabled())
        self.assertEqual(len(region.countries()), 10)
        for name, lat, lon in [("Pretoria", -25.746, 28.188), ("Maseru (a hole in South Africa)", -29.310, 27.478),
                               ("Windhoek", -22.560, 17.083), ("Lilongwe", -13.963, 33.774),
                               ("Zanzibar Town", -6.165, 39.199)]:
            self.assertTrue(region.contains(lat, lon), name)
        for name, lat, lon in [("Luanda", -8.839, 13.289), ("Nairobi", -1.286, 36.817),
                               ("Antananarivo", -18.879, 47.508), ("Mount Whitney", 36.5785, -118.2923)]:
            self.assertFalse(region.contains(lat, lon), name)

    def test_the_margin(self):
        self.assertTrue(region.contains(-34.0886, 18.3406), "2 km off Chapman's Peak")
        self.assertFalse(region.contains(-34.0886, 18.1606), "20 km out to sea")

    def test_no_polygons_opens_the_planet(self):
        region.set_data({"name": "x", "countries": [], "polygons": []})
        self.assertFalse(region.enabled())
        self.assertEqual(region.name(), "")
        self.assertTrue(region.contains(36.5785, -118.2923))

    def test_the_mod_has_the_same_polygons(self):
        with open(LUA, encoding="utf-8") as fh:
            lua = fh.read()
        nums = [float(x) for x in re.findall(r"-?\d+\.?\d*(?:e-?\d+)?", lua.split("polygons = {", 1)[1])]
        region.set_data()
        want = [v for p in region._data["polygons"] for r in p["rings"] for v in r]
        self.assertEqual(nums, want)


if __name__ == "__main__":
    unittest.main()
