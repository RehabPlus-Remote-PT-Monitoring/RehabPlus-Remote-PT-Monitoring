<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Model;

class StaffTimeOff extends Model
{
    protected $table = 'staff_time_offs';

    protected $fillable = [
        'staff',
        'date',
        'type',
        'time',
        'reason',
    ];

    protected $casts = [
        'date' => 'date',
    ];
}
