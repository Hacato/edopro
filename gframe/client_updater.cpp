void ClientUpdater::Unzip(void* payload, unzip_callback callback) {
	Utils::SetThreadName("Unzip");

#if EDOPRO_WINDOWS || EDOPRO_LINUX
	const auto& path = ygo::Utils::GetExePath();
	const auto oldpath = epro::format(EPRO_TEXT("{}.old"), path);
	if(!Utils::FileMove(path, oldpath)) {
		ErrorLog("[Realm Updater] FAILED: Could not move the running executable.");
		failed = true;
		return;
	}
#endif

	unzip_payload cbpayload{};
	UnzipperPayload uzpl{};
	uzpl.payload = payload;
	uzpl.tot = static_cast<int>(update_urls.size());
	cbpayload.payload = &uzpl;

	int i = 1;
	for(const auto& file : update_urls) {
		uzpl.cur = i++;
		const auto name = epro::format(
			UPDATES_FOLDER,
			ygo::Utils::ToPathString(file.name)
		);
		uzpl.filename = name.data();

		if(!Utils::UnzipArchive(name, callback, &cbpayload)) {
			ErrorLog(
				"[Realm Updater] FAILED: Could not extract update archive: {}",
				file.name
			);
			failed = true;
			break;
		}
	}

#if EDOPRO_WINDOWS || EDOPRO_LINUX
	if(failed || !Utils::FileExists(path)) {
		Utils::FileDelete(path);
		Utils::FileMove(oldpath, path);
		ErrorLog(
			"[Realm Updater] FAILED: Update not installed; restored the previous executable."
		);
		failed = true;
		return;
	}
#endif

	Utils::Reboot();
}
