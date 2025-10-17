# PULLMED
📱 Medical Record Application with NFC Integration

Application and site for the project PULLMED, a wristband with NFC for emergencies 


🩺 Overview

This project consists of a cross-platform mobile application (Android and iOS) developed for the registration, storage,  and NFC-based encoding of personal medical information.
The application was designed as part of an academic research project aimed at evaluating the usability, reliability, and data management efficiency of mobile health systems.

⚙️ Technologies and Development Environment

Flutter / Dart	--> Cross-platform mobile development
Visual Studio Code (VSCode) -->	Development environment
Android Studio -->	Android emulator and debugging
Xcode	--> iOS simulator and testing
Supabase --> Backend service and remote database
NFC Tool Kit -->	NFC read/write communication library

🧩 Application Structure

The system is divided into three main interfaces:
      Login Page – Handles user authentication and access control.
      Medical Record Page – Enables users to enter and manage their medical data.
      NFC Writing Page – Generates a unique user-specific URL (linked to the authenticated account) and writes it to an NFC tag using the integrated toolkit.

🔄 Data Flow and System Architecture

The user logs in through the authentication system integrated with Supabase.
After authentication, the user accesses the Medical Record interface and fills in personal and clinical information.
Data are securely stored in the remote Supabase database.
Upon confirmation, the system generates a unique URL associated with the user’s login credentials.
This URL is written to an NFC tag through the NFC Tool Kit library, enabling offline identification and data retrieval.

The application follows a client–server architecture, where the mobile app acts as the client, Supabase functions as the backend service, and the NFC tag serves as an auxiliary physical data layer.

🚀 Installation and Execution

Prerequisites:
Flutter SDK installed
Android or iOS emulator (or physical device with NFC support)

🧾 License

This project is released under the terms of the MIT License.
See the LICENSE file for details.
