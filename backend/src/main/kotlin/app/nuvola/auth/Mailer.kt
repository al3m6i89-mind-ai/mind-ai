package app.nuvola.auth

import app.nuvola.config.AppProperties
import org.slf4j.LoggerFactory
import org.springframework.beans.factory.ObjectProvider
import org.springframework.mail.SimpleMailMessage
import org.springframework.mail.javamail.JavaMailSender
import org.springframework.stereotype.Service

@Service
class Mailer(private val props: AppProperties, private val sender: ObjectProvider<JavaMailSender>) {
    private val log = LoggerFactory.getLogger(javaClass)

    fun send(to: String, subject: String, body: String) {
        if (props.mail.transport == "log") {
            // Development only: StartupGuards blocks this transport in production.
            log.info("[mail:log] to={} subject={}\n{}", to, subject, body)
            return
        }
        val mail = SimpleMailMessage().apply {
            from = props.mail.from
            setTo(to)
            this.subject = subject
            text = body
        }
        sender.getObject().send(mail)
    }
}
