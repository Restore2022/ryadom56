import logging
import smtplib
import ssl
from email.header import Header
from email.message import EmailMessage
from email.utils import formataddr

from app.core.config import settings

logger = logging.getLogger(__name__)


class MailNotConfigured(RuntimeError):
    pass


class MailSendError(RuntimeError):
    pass


def mail_configured() -> bool:
    return bool((settings.smtp_host or "").strip() and (settings.smtp_user or "").strip() and (settings.smtp_password or "").strip())


def send_email(*, to: str, subject: str, text: str, html: str | None = None) -> None:
    if not mail_configured():
        raise MailNotConfigured("SMTP is not configured")
    from_addr = (settings.smtp_from or settings.smtp_user).strip()
    msg = EmailMessage()
    msg["Subject"] = str(Header(subject, "utf-8"))
    msg["From"] = formataddr((settings.smtp_from_name, from_addr))
    msg["To"] = to
    msg.set_content(text, charset="utf-8")
    if html:
        msg.add_alternative(html, subtype="html")

    host = settings.smtp_host.strip()
    port = int(settings.smtp_port or 465)
    user = settings.smtp_user.strip()
    password = settings.smtp_password
    use_ssl = bool(settings.smtp_use_ssl) or port == 465
    try:
        context = ssl.create_default_context()
        if use_ssl:
            with smtplib.SMTP_SSL(host, port, timeout=20, context=context) as smtp:
                smtp.login(user, password)
                smtp.send_message(msg)
        else:
            with smtplib.SMTP(host, port, timeout=20) as smtp:
                smtp.ehlo()
                if settings.smtp_use_tls or port == 587:
                    smtp.starttls(context=context)
                    smtp.ehlo()
                smtp.login(user, password)
                smtp.send_message(msg)
    except MailNotConfigured:
        raise
    except Exception as exc:
        logger.warning("SMTP send failed to=%s: %s", to, exc)
        raise MailSendError("send failed") from exc
    logger.info("SMTP sent to=%s subject=%s", to, subject)
