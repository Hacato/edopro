#include "client_updater.h"
#if defined(UPDATE_URL) && !EDOPRO_IOS
#include "config.h"
#if EDOPRO_WINDOWS
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#elif EDOPRO_LINUX || EDOPRO_APPLE
#include <sys/file.h>
#include <sys/stat.h>
#include <unistd.h>
#include <sys/wait.h>
#endif //EDOPRO_WINDOWS
#include "file_stream.h"
#include <nlohmann/json.hpp>
#include <atomic>
#include "logging.h"
#include "epro_thread.h"
#include "utils.h"
#include "porting.h"
#include "game_config.h"
#include "fmt.h"
#include "curl.h"
#include "crypto.h"

#define LOCKFILE EPRO_TEXT("./.edopro_lock")
#define UPDATES_FOLDER EPRO_TEXT("./updates/{}")

struct WritePayload {
	std::vector<char>* outbuffer = nullptr;
	std::ostream* outstream = nullptr;
	epro::MD5Context* md5context = nullptr;
};

struct Payload {
	update_callback callback = nullptr;
	int current = 1;
	int total = 1;
	bool is_new = true;
	int previous_percent = 0;
	void* payload = nullptr;
	const char* filename = nullptr;
};

template<typename off_type>
static int progress_callback(void* ptr, off_type TotalToDownload, [[maybe_unused]] off_type NowDownloaded, [[maybe_unused]] off_type TotalToUpload, off_type NowUploaded) {
	Payload* payload = static_cast<Payload*>(ptr);
	if(payload && payload->callback) {
		int percentage = 0;
		if(TotalToDownload > static_cast<off_type>(0)) {
			double fractiondownloaded = static_cast<double>(NowDownloaded) / static_cast<double>(TotalToDownload);
			percentage = static_cast<int>(std::round(fractiondownloaded * 100));
		}
		if(percentage != payload->previous_percent) {
			payload->callback(percentage, payload->current, payload->total, payload->filename, payload->is_new, payload->payload);
			payload->is_new = false;
			payload->previous_percent = percentage;
		}
	}
	return 0;
}

static size_t WriteCallback(char *contents, size_t size, size_t nmemb, void *userp) {
	size_t readsize = size * nmemb;
	auto* payload = static_cast<WritePayload*>(userp);
	if(auto buff = payload->outbuffer; buff)
		buff->insert(buff->end(), contents, contents + readsize);
	if(payload->outstream)
		payload->outstream->write(contents, readsize);
	if(payload->md5context)
		payload->md5context->update(contents, readsize);
	return readsize;
}

static CURLcode curlPerform(const char* url, void* payload, void* payload2 = nullptr) {
	char curl_error_buffer[CURL_ERROR_SIZE]{};
	auto curl_handle = curl_easy_init();

	if(!curl_handle) {
		ygo::ErrorLog("[Realm Updater] curl_easy_init failed for URL: {}", url);
		return CURLE_FAILED_INIT;
	}

	curl_easy_setopt(curl_handle, CURLOPT_ERRORBUFFER, curl_error_buffer);
	curl_easy_setopt(curl_handle, CURLOPT_FAILONERROR, 1L);
	curl_easy_setopt(curl_handle, CURLOPT_URL, url);
	curl_easy_setopt(curl_handle, CURLOPT_WRITEFUNCTION, WriteCallback);
	curl_easy_setopt(curl_handle, CURLOPT_CONNECTTIMEOUT, 60L);
	curl_easy_setopt(curl_handle, CURLOPT_WRITEDATA, payload);
	const auto& realm_user_agent = ygo::Utils::GetUserAgent();
	ygo::ErrorLog("[Realm Updater] User-Agent: {}", realm_user_agent);
	curl_easy_setopt(curl_handle, CURLOPT_USERAGENT, realm_user_agent.c_str());
	curl_easy_setopt(curl_handle, CURLOPT_NOPROXY, "*");
	curl_easy_setopt(curl_handle, CURLOPT_FOLLOWLOCATION, 1L);

#if (LIBCURL_VERSION_NUM >= CURL_VERSION_BITS(7,32,0))
	if(curl_easy_setopt(curl_handle, CURLOPT_XFERINFOFUNCTION, progress_callback<curl_off_t>) == CURLE_OK) {
		curl_easy_setopt(curl_handle, CURLOPT_XFERINFODATA, payload2);
	} else
#endif
	{
		curl_easy_setopt(curl_handle, CURLOPT_PROGRESSFUNCTION, progress_callback<double>);
		curl_easy_setopt(curl_handle, CURLOPT_PROGRESSDATA, payload2);
	}

	curl_easy_setopt(curl_handle, CURLOPT_NOPROGRESS, 0L);

	if(ygo::gGameConfig->ssl_certificate_path.size()
	   && ygo::Utils::FileExists(ygo::Utils::ToPathString(ygo::gGameConfig->ssl_certificate_path)))
		curl_easy_setopt(curl_handle, CURLOPT_CAINFO, ygo::gGameConfig->ssl_certificate_path.data());

	auto res = curl_easy_perform(curl_handle);

	if(res != CURLE_OK) {
		ygo::ErrorLog(
			"[Realm Updater] CURL FAILED: code={} message={} details={} URL={}",
			static_cast<int>(res),
			curl_easy_strerror(res),
			curl_error_buffer,
			url
		);
	}

	curl_easy_cleanup(curl_handle);
	return res;
}

namespace ygo {

void ClientUpdater::StartUnzipper(unzip_callback callback, void* payload) {
#if EDOPRO_ANDROID
	porting::installUpdate(epro::format("{}" UPDATES_FOLDER ".apk", Utils::GetWorkingDirectory(), update_urls.front().name));
#else
	if(Lock.acquired())
		epro::thread(&ClientUpdater::Unzip, this, payload, callback).detach();
#endif
}

void ClientUpdater::CheckUpdates() {
	if(Lock.acquired())
		epro::thread(&ClientUpdater::CheckUpdate, this).detach();
}

bool ClientUpdater::StartUpdate(update_callback callback, void* payload) {
	if(!Lock.acquired() || !has_update || downloading)
		return false;
	epro::thread(&ClientUpdater::DownloadUpdate, this, payload, callback).detach();
	return true;
}

void ClientUpdater::Unzip(void* payload, unzip_callback callback) {
	Utils::SetThreadName("Unzip");

#if EDOPRO_WINDOWS || EDOPRO_LINUX
	const auto& path = ygo::Utils::GetExePath();
	Utils::FileMove(path, epro::format(EPRO_TEXT("{}.old"), path));
#endif

#if EDOPRO_WINDOWS
	const auto& corepath = ygo::Utils::GetCorePath();
	Utils::FileMove(corepath, epro::format(EPRO_TEXT("{}.old"), corepath));
#endif

	Utils::Reboot();
}

#if EDOPRO_ANDROID
#define formatstr (UPDATES_FOLDER EPRO_TEXT(".apk"))
#else
#define formatstr UPDATES_FOLDER
#endif

void ClientUpdater::DownloadUpdate(void* payload, update_callback callback) {
	Utils::SetThreadName("Updater");
	downloading = true;

	ErrorLog("[Realm Updater] ===== DOWNLOAD START =====");
	ErrorLog("[Realm Updater] Assets to download: {}", update_urls.size());

	Payload cbpayload{};
	cbpayload.callback = callback;
	cbpayload.total = static_cast<int>(update_urls.size());
	cbpayload.payload = payload;

	int cur_file = 1;

	for(auto& file : update_urls) {
		auto name = epro::format(formatstr, ygo::Utils::ToPathString(file.name));

		ErrorLog("[Realm Updater] Asset name: {}", file.name);
		ErrorLog("[Realm Updater] Asset URL: {}", file.url);
		ErrorLog("[Realm Updater] Expected MD5: {}", file.md5);

		cbpayload.current = cur_file++;
		cbpayload.filename = file.name.data();
		cbpayload.is_new = true;
		cbpayload.previous_percent = -1;

		epro::MD5Context::digest binmd5;

		if(file.md5.size() != binmd5.size() * 2) {
			ErrorLog(
				"[Realm Updater] FAILED: MD5 string has wrong length. Got {}, expected {}.",
				file.md5.size(),
				binmd5.size() * 2
			);
			failed = true;
			continue;
		}

		try {
			for(size_t i = 0; i < binmd5.size(); i++) {
				uint8_t b = static_cast<uint8_t>(
					std::stoul(file.md5.substr(i * 2, 2), nullptr, 16)
				);
				binmd5[i] = b;
			}
		} catch(...) {
			ErrorLog("[Realm Updater] FAILED: Could not parse MD5 string.");
			failed = true;
			continue;
		}

		ErrorLog("[Realm Updater] MD5 string parsed successfully.");

		if(epro::calculateMD5(name) == binmd5) {
			ErrorLog("[Realm Updater] Existing update file already has correct MD5. Skipping download.");
			continue;
		}

		ErrorLog("[Realm Updater] Existing file absent or MD5 differs. Preparing download.");

		if(!ygo::Utils::CreatePath(name)) {
			ErrorLog("[Realm Updater] FAILED: Utils::CreatePath returned false.");
			failed = true;
			continue;
		}

		ErrorLog("[Realm Updater] CreatePath succeeded.");

		bool this_failed = false;

		{
			FileStream stream{
				name,
				FileStream::out | FileStream::binary | FileStream::trunc
			};

			if(stream.fail()) {
				ErrorLog("[Realm Updater] FAILED: Could not open destination update file for writing.");
				failed = true;
				continue;
			}

			ErrorLog("[Realm Updater] Destination file opened successfully.");
			ErrorLog("[Realm Updater] Beginning CURL download...");

			WritePayload wpayload;
			wpayload.outstream = &stream;

			epro::MD5Context context{};
			wpayload.md5context = &context;

			const auto curl_result = curlPerform(
				file.url.data(),
				&wpayload,
				&cbpayload
			);

			if(curl_result != CURLE_OK) {
				ErrorLog(
					"[Realm Updater] FAILED: curlPerform returned CURL code {}.",
					static_cast<int>(curl_result)
				);
				this_failed = failed = true;
			} else {
				ErrorLog("[Realm Updater] CURL download completed successfully.");

				const auto downloaded_md5 = context.final();

				if(downloaded_md5 != binmd5) {
					ErrorLog("[Realm Updater] FAILED: Downloaded file MD5 does not match update.json.");
					this_failed = failed = true;
				} else {
					ErrorLog("[Realm Updater] Downloaded file MD5 matches.");
				}
			}
		}

		if(this_failed) {
			ErrorLog("[Realm Updater] Removing failed update file.");
			Utils::FileDelete(name);
		} else {
			ErrorLog("[Realm Updater] Asset download completed successfully.");
		}
	}

	downloaded = true;

	ErrorLog(
		"[Realm Updater] ===== DOWNLOAD FINISHED. failed={} =====",
		failed.load()
	);
}

void ClientUpdater::CheckUpdate() {
	Utils::SetThreadName("CheckUpdate");

	WritePayload payload{};
	std::vector<char> retrieved_data;
	payload.outbuffer = &retrieved_data;

	ErrorLog("[Realm Updater] Checking update URL: {}", update_url);

	if(curlPerform(update_url.data(), &payload) != CURLE_OK) {
		ErrorLog("[Realm Updater] FAILED: Could not retrieve update JSON.");
		return;
	}

	ErrorLog(
		"[Realm Updater] Update endpoint returned {} bytes.",
		retrieved_data.size()
	);

	try {
		const auto j = nlohmann::json::parse(retrieved_data);

		if(!j.is_array()) {
			ErrorLog("[Realm Updater] FAILED: Update JSON root is not an array.");
			return;
		}

		for(const auto& asset : j) {
			try {
				const auto& url = asset.at("url").get_ref<const std::string&>();
				const auto& name = asset.at("name").get_ref<const std::string&>();
				const auto& md5 = asset.at("md5").get_ref<const std::string&>();

				ErrorLog(
					"[Realm Updater] Update asset received: name={} url={} md5={}",
					name,
					url,
					md5
				);

				update_urls.emplace_back(
					DownloadInfo{ name, url, md5 }
				);
			} catch(...) {
				ErrorLog("[Realm Updater] WARNING: Invalid asset entry in update JSON.");
			}
		}
	}
	catch(...) {
		ErrorLog("[Realm Updater] FAILED: Could not parse update JSON.");
		update_urls.clear();
	}

	has_update = !!update_urls.size();

	ErrorLog(
		"[Realm Updater] Update check finished. has_update={} assets={}",
		has_update ? 1 : 0,
		update_urls.size()
	);
}

static inline void DeleteOld() {
#if EDOPRO_WINDOWS || EDOPRO_LINUX
	ygo::Utils::FileDelete(
		epro::format(
			EPRO_TEXT("{}.old"),
			ygo::Utils::GetExePath()
		)
	);
#endif

#if EDOPRO_WINDOWS
	ygo::Utils::FileDelete(
		epro::format(
			EPRO_TEXT("{}.old"),
			ygo::Utils::GetCorePath()
		)
	);
#endif

	(void)0;
}

ClientUpdater::ClientUpdater(epro::path_stringview override_url) {
	if(override_url.size())
		update_url = Utils::ToUTF8IfNeeded(override_url);

	if(Lock.acquired())
		DeleteOld();
}

#if EDOPRO_WINDOWS || EDOPRO_LINUX || EDOPRO_MACOS

ClientUpdater::FileLock::FileLock() {
#if EDOPRO_WINDOWS
	m_lock = CreateFile(
		LOCKFILE,
		GENERIC_READ,
		0,
		nullptr,
		CREATE_ALWAYS,
		FILE_ATTRIBUTE_HIDDEN,
		nullptr
	);

	if(m_lock == INVALID_HANDLE_VALUE)
		m_lock = null_lock;
#else
	m_lock = open(
		LOCKFILE,
		O_CREAT | O_CLOEXEC,
		S_IRWXU
	);

	if(m_lock < 0 || flock(m_lock, LOCK_EX | LOCK_NB) != 0) {
		close(m_lock);
		m_lock = null_lock;
	}
#endif
}

ClientUpdater::FileLock::~FileLock() {
	if(m_lock == null_lock)
		return;

#if EDOPRO_WINDOWS
	CloseHandle(m_lock);
#else
	flock(m_lock, LOCK_UN);
	close(m_lock);
#endif

	ygo::Utils::FileDelete(LOCKFILE);
}

#endif

}

#endif //UPDATE_URL
