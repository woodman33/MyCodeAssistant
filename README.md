# Xcode AI Code Assistant - Setup Guide

The script has created the necessary source files. Now, follow these steps in Xcode to complete the setup.

## 1. Create the Xcode Project

1.  Open Xcode and select **Create a new Xcode project**.
2.  Choose the **macOS > App** template and click **Next**.
3.  For "Product Name", enter **MyCodeAssistant**.
4.  Ensure the "Interface" is set to **SwiftUI** and "Language" is **Swift**.
5.  Save the project inside the MyCodeAssistant directory that was just created by the script. This is important so Xcode can find the files.

## 2. Add the Extension Target

1.  With your project open, go to **File > New > Target...**.
2.  Select the **macOS > Xcode Source Editor Extension** template and click **Next**.
3.  For "Product Name", enter **AICommand** and click **Finish**.
4.  When prompted to activate the scheme, click **Activate**.

## 3. Replace the Source Files

1.  In the Xcode Project Navigator, locate the AICommand folder.
2.  Delete the SourceEditorCommand.swift and Info.plist files that Xcode automatically created inside the AICommand folder.
3.  Click the **Add Files to "MyCodeAssistant"...** button (or go to **File > Add Files...**).
4.  Navigate to the MyCodeAssistant/AICommand folder, select the SourceEditorCommand.swift and Info.plist files that the script created, and add them to the project. Make sure they are added to the AICommand target.

## 4. Get API Key & Run

1.  Follow the original instructions to get a Gemini API key.
2.  Select the **AICommand** scheme and run it. Choose Xcode as the target application.
3.  The first time you use the command from the **Editor** menu, it will ask for your API key.
