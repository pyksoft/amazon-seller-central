class UserMailer < ActionMailer::Base
  default from: 'roiekoper@gmail.com'

  def send_email(content, title, to)
    mail(
        # body: content + " <img src= 'http://fierce-cliffs-7678.herokuapp.com/assets/thank.jpeg',style='width:100%;height:100%' >",
        body: content,
        subject: title,
        to: to,
        content_type: 'text/html'
    )
  end
end