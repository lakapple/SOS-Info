# Android Client - SOS Flood App

Đây là mã nguồn cho **Android Client** của hệ thống bản đồ cứu trợ thiên tai SOS. Ứng dụng này được xây dựng bằng **Flutter**, đóng vai trò là cầu nối giữa người gặp nạn với hệ thống máy chủ thông qua đội cứu hộ và các tình nguyện viên.

Ứng dụng tập trung vào khả năng hoạt động trong điều kiện khẩn cấp, tích hợp AI để xử lý tin nhắn SOS tự động và định vị chính xác.

## 📱 Tính năng nổi bật

### 1. 🤖 Tự động xử lý tin nhắn SOS (AI Powered)
*   **Lắng nghe SMS:** Tự động phát hiện các tin nhắn đến có chứa từ khóa khẩn cấp (ví dụ: `sos`, `cuu`, `help`).
*   **Trích xuất thông tin thông minh:** Sử dụng model **gemini-2.5-flash-lite** để phân tích nội dung tin nhắn tự nhiên, trích xuất:
    *   Số điện thoại liên hệ.
    *   Địa chỉ người gặp nạn.
    *   Số lượng người cần cứu.
    *   Loại yêu cầu (Y tế, Nhu yếu phẩm, Di dời...).

### 2. 📍 Định vị & Gửi yêu cầu
*   **GPS Tracking:** Lấy tọa độ chính xác (Latitude/Longitude) của thiết bị để gửi lên hệ thống bản đồ.
*   **Form xác nhận:** Cho phép người dùng chỉnh sửa lại thông tin do AI trích xuất trước khi gửi để đảm bảo tính chính xác.

### 3. 🗺️ Bản đồ & Dữ liệu thời gian thực
*   **Kết nối linh hoạt:** Ứng dụng có thể kết nối tới **Official Server** hoặc các **Community Node** gần nhất để tải dữ liệu bản đồ, giúp giảm tải và tăng tốc độ truy cập.
*   **Hiển thị:** Xem danh sách các điểm cứu trợ, các hộ dân đang kêu cứu trên giao diện trực quan (WebView tích hợp).

### 4. ⚙️ Cấu hình linh hoạt
*   Tùy chọn bật/tắt chế độ tự động gửi (Auto-send).
*   Tùy chỉnh khoảng thời gian làm mới dữ liệu (Refresh Interval).
*   Quản lý API Key cho AI.

## 🛠 Yêu cầu kỹ thuật

*   **Flutter SDK**: 3.x trở lên.
*   **Android SDK**: Hỗ trợ tối thiểu Android 6.0 (API 23), khuyến nghị Android 10+.
*   **Thiết bị thật**: Khuyên dùng để test tính năng SMS và GPS (Emulator thường bị hạn chế các tính năng này).

## 📦 Cài đặt & Chạy (Development)

### 1. Clone repository
```bash
git clone https://github.com/lakapple/SOS-Info.git
cd SOS-Info
```

### 2. Cài đặt dependencies
```bash
flutter pub get
```

### 4. Chạy ứng dụng
Kết nối thiết bị Android và chạy:
```bash
flutter run
```

## 🔒 Quyền hạn (Permissions)

Ứng dụng yêu cầu các quyền nhạy cảm sau để hoạt động đúng chức năng cứu hộ:

*   `android.permission.RECEIVE_SMS`: Để phát hiện tin nhắn SOS đến ngay lập tức.
*   `android.permission.READ_SMS`: Để đọc nội dung tin nhắn phục vụ phân tích AI.
*   `android.permission.ACCESS_FINE_LOCATION`: Để lấy tọa độ chính xác của người dùng gửi lên bản đồ.
*   `android.permission.INTERNET`: Để kết nối với Server và Gemini AI.

## 🤝 Đóng góp

Chúng tôi hoan nghênh mọi đóng góp để cải thiện khả năng nhận diện tin nhắn tiếng Việt hoặc tối ưu hóa giao diện người dùng.

## LICENSE

Copyright (c) 2025 Nexuron.
Copyright (c) 2025 Nexuron Licensed under the Nexuron Custom License — see LICENSE.
