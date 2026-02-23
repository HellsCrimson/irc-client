.PHONY: get run release icons clean

get:
	flutter pub get

run:
	flutter run

release:
	flutter run --release

icons:
	flutter pub run flutter_launcher_icons

clean:
	flutter clean
