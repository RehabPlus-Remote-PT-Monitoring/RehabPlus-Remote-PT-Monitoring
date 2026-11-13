<?php

namespace App\Services\Firebase;

/** A commit's precondition failed: the document changed since it was read. */
class FirestoreConflict extends FirebaseException
{
}
