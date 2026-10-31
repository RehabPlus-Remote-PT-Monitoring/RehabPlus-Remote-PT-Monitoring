<?php

namespace App\Helpers;

/**
 * Phone numbers are stored as "+" followed by the country code and the national number,
 * for example +639171234567. The form picks the country, and the national number must have
 * the digits that country uses for mobile numbers (no trunk "0", no spaces).
 */
class PhoneNumber
{
    public const DEFAULT_COUNTRY = 'PH';

    /** iso => [name, dial code, min digits, max digits, example national number] */
    private const COUNTRIES = [
        'PH' => ['Philippines', '63', 10, 10, '9171234567'],
        'US' => ['United States', '1', 10, 10, '2025550123'],
        'GB' => ['United Kingdom', '44', 10, 10, '7400123456'],
        'AU' => ['Australia', '61', 9, 9, '412345678'],
        'NZ' => ['New Zealand', '64', 8, 10, '212345678'],
        'SG' => ['Singapore', '65', 8, 8, '81234567'],
        'MY' => ['Malaysia', '60', 9, 10, '123456789'],
        'ID' => ['Indonesia', '62', 9, 12, '812345678'],
        'TH' => ['Thailand', '66', 9, 9, '812345678'],
        'VN' => ['Vietnam', '84', 9, 9, '912345678'],
        'JP' => ['Japan', '81', 10, 10, '9012345678'],
        'KR' => ['South Korea', '82', 10, 11, '1012345678'],
        'CN' => ['China', '86', 11, 11, '13812345678'],
        'IN' => ['India', '91', 10, 10, '9876543210'],
        'HK' => ['Hong Kong', '852', 8, 8, '91234567'],
        'TW' => ['Taiwan', '886', 9, 9, '912345678'],
        'AE' => ['United Arab Emirates', '971', 9, 9, '501234567'],
        'SA' => ['Saudi Arabia', '966', 9, 9, '512345678'],
        'QA' => ['Qatar', '974', 8, 8, '33123456'],
        'KW' => ['Kuwait', '965', 8, 8, '50012345'],
        'DE' => ['Germany', '49', 10, 11, '15123456789'],
        'FR' => ['France', '33', 9, 9, '612345678'],
        'IT' => ['Italy', '39', 9, 10, '3123456789'],
        'ES' => ['Spain', '34', 9, 9, '612345678'],
        'NL' => ['Netherlands', '31', 9, 9, '612345678'],
        'BR' => ['Brazil', '55', 11, 11, '11912345678'],
        'MX' => ['Mexico', '52', 10, 10, '5512345678'],
    ];

    /** @return list<array{iso: string, name: string, dial: string, min: int, max: int, digits: string, example: string}> */
    public static function countries(): array
    {
        return collect(self::COUNTRIES)
            ->map(fn (array $country, string $iso) => [
                'iso' => $iso,
                'name' => $country[0],
                'dial' => $country[1],
                'min' => $country[2],
                'max' => $country[3],
                'digits' => $country[2] === $country[3] ? "{$country[2]} digits" : "{$country[2]}–{$country[3]} digits",
                'example' => $country[4],
            ])
            ->values()
            ->all();
    }

    /** @return list<string> */
    public static function isoCodes(): array
    {
        return array_keys(self::COUNTRIES);
    }

    /** Null when the national number is valid for the country, otherwise the message to show. */
    public static function problem(string $iso, string $national): ?string
    {
        [$name, , $min, $max] = self::COUNTRIES[$iso];

        if (! ctype_digit($national)) {
            return 'Phone number can only contain numbers.';
        }

        $length = strlen($national);
        if ($length >= $min && $length <= $max) {
            return null;
        }

        return $min === $max
            ? "Enter exactly {$min} digits for the phone number in {$name}."
            : "Enter {$min} to {$max} digits for the phone number in {$name}.";
    }

    /** The stored form: "+" plus the country code and the national number. */
    public static function toStored(string $iso, string $national): string
    {
        return '+'.self::COUNTRIES[$iso][1].$national;
    }

    /**
     * The country and national number of a stored phone. Numbers saved before country codes
     * had no "+" and were taken as Philippine numbers, so a leading trunk "0" is dropped.
     *
     * @return array{iso: string, national: string}
     */
    public static function parse(?string $stored): array
    {
        $stored = trim((string) $stored);
        $digits = preg_replace('/\D/', '', $stored);

        if (str_starts_with($stored, '+')) {
            $match = collect(self::COUNTRIES)
                ->filter(fn (array $country) => str_starts_with($digits, $country[1]))
                ->sortByDesc(fn (array $country) => strlen($country[1]))
                ->keys()
                ->first();

            if ($match !== null) {
                return ['iso' => $match, 'national' => substr($digits, strlen(self::COUNTRIES[$match][1]))];
            }
        }

        return [
            'iso' => self::DEFAULT_COUNTRY,
            'national' => str_starts_with($digits, '0') ? substr($digits, 1) : $digits,
        ];
    }
}
