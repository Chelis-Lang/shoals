Shoals date APIs now use `Std.Datetime.Date`, replacing the removed
`Std.Time.Date` type. Import date constructors and accessors from
`Std.Datetime`; date fields are opaque and years outside -9999 through 9999
fail loudly. The package requires Chelis 0.18.13.
