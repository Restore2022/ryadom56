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
    ]
    admin_email: str = "admin@ryadom56.ru"
    admin_password: str = "admin123"
    admin_name: str = "Администратор"

    class Config:
        env_file = ".env"


settings = Settings()
