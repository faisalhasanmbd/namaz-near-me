# Namaz Near Me Flutter App Source

This folder contains the Android-first Flutter app source for the MVP.

Flutter is not currently installed on this machine, so this is a source scaffold. After Flutter is installed, create the full platform project and copy/keep this `lib` folder.

Suggested setup:

```bash
flutter create namaz_near_me_android
cp -R mobile-flutter/lib namaz_near_me_android/lib
cd namaz_near_me_android
flutter run
```

The current source uses sample mosque data. Supabase integration should be added after the database is created.

