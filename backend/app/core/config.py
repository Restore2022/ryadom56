from pydantic_settings import BaseSettings


class Settings(BaseSettings):
    app_name: str = "Рядом56"
    secret_key: str = "ryadom56-dev-secret-change-me-in-production"
    algorithm: str = "HS256"
    access_token_expire_minutes: int = 60 * 24 * 7  # 7 days
    database_url: str = "sqlite:///./data/ryadom56.db"
    cors_origins: list[str] = [
        "http://localhost:5173",
        "http://127.0.0.1:5173",
        "http://localhost:3000",
        "https://legac.ru",
        "https://www.legac.ru",
    ]
    admin_email: str = "admin@ryadom56.ru"
    admin_password: str = "admin123"
    admin_name: str = "Администратор"
    # FCM HTTP v1 (Legacy API отключён в Firebase)
    fcm_project_id: str = "ryadom56"
    fcm_service_account_file: str = ""  # путь к JSON service account
    fcm_server_key: str = ""  # устарело, не используется
    # Демо-контент (ярмарки, маршруты-заглушки) только для локальной разработки
    seed_demo_content: bool = False
    # SMTP для восстановления пароля
    smtp_host: str = ""
    smtp_port: int = 465
    smtp_user: str = ""
    smtp_password: str = ""
    smtp_from: str = ""
    smtp_from_name: str = "Рядом56"
    smtp_use_ssl: bool = True
    smtp_use_tls: bool = False
    password_reset_ttl_minutes: int = 20

    class Config:
        env_file = ".env"


settings = Settings()
