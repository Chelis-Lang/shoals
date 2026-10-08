The accuracy oracle tests now require a diagnostic for NaN, infinite, and
missing normal-CDF left-tail results. A NaN at any swept point must fail,
including when every result is NaN.
