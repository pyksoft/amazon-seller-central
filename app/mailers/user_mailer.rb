class UserMailer < ActionMailer::Base
  default from: 'idanshviro@gmail.com'

  def send_email(content, title, to)
    [*to].each do |to_mail|
      mail(
          # body: content + " <img src= 'http://fierce-cliffs-7678.herokuapp.com/assets/thank.jpeg',style='width:100%;height:100%' >",
          body: content,
          subject: title,
          to: to_mail,
          content_type: 'text/html'
      )
    end
  end


  def send_html_email(content, title, to)
    [*to].each do |to_mail|
      mail(
          body: content,
          subject: title,
          to: to_mail,
          content_type: 'text/html'
      )
    end
  end
end
