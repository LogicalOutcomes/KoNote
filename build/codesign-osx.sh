# script to codesign app on osx

# to find the correct cert (identity), run the following (we need the 'Developer ID Application'):
# $ security find-identity

identity="3E917C28F1E8796101B29EC82714298CB4F7F33C"

echo ">>> signing app"
codesign -f -i "ca.konode.konote" -s "$identity" "KoNote.app/Contents/Frameworks/crash_inspector"
codesign -f -i "ca.konode.konote" -s "$identity" "KoNote.app/Contents/Frameworks/node-webkit Framework.framework"
codesign -f -i "ca.konode.konote" -s "$identity" "KoNote.app/Contents/Frameworks/node-webkit Helper EH.app"
codesign -f -i "ca.konode.konote" -s "$identity" "KoNote.app/Contents/Frameworks/node-webkit Helper NP.app"
codesign -f -i "ca.konode.konote" -s "$identity" "KoNote.app/Contents/Frameworks/node-webkit Helper.app"
codesign -f -i "ca.konode.konote" -s "$identity" "KoNote.app"

#echo ">>> verifying signature"
#sudo spctl -a -v "KoNote.app"

echo ">>> done!"
