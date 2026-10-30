#ifndef OASIS_CORE_H_
#define OASIS_CORE_H_

#include <unistd.h>

#include <cstdint>
#include <functional>
#include <map>
#include <memory>
#include <string>
#include <variant>
#include <vector>

struct Oval {
  using List = std::vector<Oval>;
  using Map = std::map<std::string, Oval>;
  std::variant<std::monostate, int64_t, double, bool, std::string, List, Map>
      v;
  Oval() = default;
  Oval(int64_t i) : v(i) {}
  Oval(int i) : v((int64_t)i) {}
  Oval(double d) : v(d) {}
  Oval(bool b) : v(b) {}
  Oval(const char* s) : v(std::string(s)) {}
  Oval(std::string s) : v(std::move(s)) {}
  Oval(List l) : v(std::move(l)) {}
  Oval(Map m) : v(std::move(m)) {}
};

using OEvent = std::map<std::string, Oval>;

struct DmabufInfo {
  int w = 0;
  int h = 0;
  uint32_t format = 0;
  int nplanes = 0;
  int fds[4] = {-1, -1, -1, -1};
  uint32_t offsets[4] = {0, 0, 0, 0};
  uint32_t strides[4] = {0, 0, 0, 0};
  uint64_t mods[4] = {0, 0, 0, 0};

  void close_fds() {
    for (int i = 0; i < 4; i++) {
      if (fds[i] >= 0) {
        ::close(fds[i]);
        fds[i] = -1;
      }
    }
  }
};

class OasisHost {
 public:
  virtual ~OasisHost() = default;
  virtual void sendEvent(OEvent fields) = 0;
  virtual int64_t createTexture(bool dmabuf) = 0;
  virtual void pushPixels(int64_t id, const uint8_t* rgba, int w, int h) = 0;
  virtual void pushDmabuf(int64_t id, const DmabufInfo& buf) = 0;
  virtual void frameAvailable(int64_t id) = 0;
  virtual void destroyTexture(int64_t id) = 0;
  virtual void outputMetrics(int& w, int& h, int& scale, int& phys_w_mm,
                             int& phys_h_mm) = 0;
  virtual std::vector<std::string> hostClipboardMimes() { return {}; }
  virtual void hostClipboardRead(
      const std::string& mime,
      std::function<void(const uint8_t*, size_t)> done) {
    done(nullptr, 0);
  }
  virtual void hostClipboardWriteText(const std::string& text) {}
};

namespace oasis { struct OasisPrivate; }

class OasisCore {
 public:
  explicit OasisCore(OasisHost* host);
  ~OasisCore();

  OasisCore(const OasisCore&) = delete;
  OasisCore& operator=(const OasisCore&) = delete;

  bool start(std::string* error);
  void stop();
  bool running() const;
  const char* socketName() const;
  const char* xwaylandDisplay() const;
  int fd() const;
  void dispatch();
  void outputChanged();
  void replayEvents();
  void configure(int64_t id, int w, int h, bool maximized, bool fullscreen,
                 bool resizing);
  void closeSurface(int64_t id);
  void focus(int64_t id);
  void pointerMotion(int64_t id, double x, double y);
  void pointerExit();
  void pointerButton(uint32_t button, bool pressed);
  void pointerAxis(double dx, double dy, uint32_t source, int32_t discrete);
  void pointerAxisStop();
  void touchDown(int64_t id, int32_t tid, double x, double y);
  void touchMotion(int32_t tid, double x, double y);
  void touchUp(int32_t tid);
  void key(uint32_t code, bool pressed);

  oasis::OasisPrivate* p = nullptr;
};

#endif
