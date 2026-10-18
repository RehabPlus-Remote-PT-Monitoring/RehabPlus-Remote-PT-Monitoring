<?php

namespace Database\Seeders;

use Illuminate\Database\Seeder;

/**
 * Nothing to seed: all dashboard data (staff accounts, patients, appointments,
 * billing, inventory, staff schedule) lives in Firebase. Create the first
 * admin with `php artisan rehab:make-admin`, then add the rest from the dashboard.
 */
class DatabaseSeeder extends Seeder
{
    public function run(): void
    {
    }
}
