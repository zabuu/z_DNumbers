# Multiple paired damage sources

Version 1.0.3 supports zBox 0.9.0 follower rosters. The optional paired-source
provider receives the requested source GUID for both damage submission and
pet-anchor visibility. It returns that same GUID only while the source remains
authorized. This keeps every follower's pet damage anchored to its own character
when the selected zBox follower changes. Legacy single-source providers that
ignore the extra argument still work. zDNumbers/MSBT retain all rendering.
