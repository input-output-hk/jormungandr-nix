{ runCommand, python3Packages }:
runCommand "jormungandr-reward-api" {} ''
  mkdir -p $out
  cp ${./app.py} $out/app.py
  cp ${./bech32.py} $out/bech32.py
''
