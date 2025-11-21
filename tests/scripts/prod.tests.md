Нужно провести полное тестирование всех graphgql endpoint

изначально нужно правилильно сгенерировать токен авторизации

ACCESS_TOKEN=$(curl -s -X POST https://api.fishboxapp.com/v2/app/user/email_login \
 -H "Content-Type: application/json" \
 -H "client-id: 2" \
 -d '{
"email": "valtesting3333@fishboxtest.com",
"password": "Qwert1234!"
}' | jq -r '.payload.access_token')

graphql endpoint будет не локальный, а на dev сервере

https://bff.fishbox.app/graphql

пример запроса

curl --request POST \
 --url https://bff.fishbox.app/graphql \
 --header 'Authorization: Bearer ACCESS_TOKEN' \
 --header 'Content-Type: application/json' \
 --header 'User-Agent: insomnia/11.1.0' \
 --header 'x-viewer-id: 63ae64480104060030be3742' \
 --data '{
"query": "mutation CreateImageUploadIntentMutation(\n $input : CreateImageUploadIntentMutationInput!\n) {\n createImageUploadIntent(input: $input) {\n\t\tpresignedForm {\n\t\t\tfields\n\t\t\tformActionUrl\n\t\t\texpires\n\t\t} \n\t\timage {\n\t\t\tid,\n\t\t\tpreviewUrl(width: 200, height: 200, quality: 85)\n\t\t}\n\n errors {\n ... on MutationError {\n code\n message\n }\n }\n }\n}\n",
"operationName": "CreateImageUploadIntentMutation",
"variables": {
"input": {
"fileName": "fish173.jpeg",
"fileMimeType": "image/jpeg",
"fileSize": 522095,
"imageWidth": 560,
"imageHeight": 854,
"fileHash": "M1rtl5oLjoBumqsRtRTNPywXDrJuPG//OgYuxZdh0AI=",
"intent": "catch.create"
}
}
}';

все header которые ты видишь в этом запросе должны быть заданы для каждого запроса

как генерировать ACCESS_TOKEN написано выше ACCESS_TOKEN живет 15 минут - нет смысла перегенерировать его на каждый запрос

обрати внимание на до как запросить ошибки в мутациях

mutation CreateImageUploadIntentMutation(
$input : CreateImageUploadIntentMutationInput!
) {
createImageUploadIntent(input: $input) {
presignedForm {
fields
formActionUrl
expires
}
image {
id,
previewUrl(width: 200, height: 200, quality: 85)
}

    errors {
      ... on MutationError {
        code
        message
      }
    }

}
}

ты часто делаешь в этом ошибки

ДОполнительные данные

список filesIds для тестирования
0199e6de-f93f-74a7-8641-33533892cdb5
0199e6df-0211-7714-b47c-a94813c12aae
0199e6df-086e-7339-ad4f-dedffb0221db
0199e6df-0f3a-713a-98eb-b2283a5c6af6
0199e6df-163b-74fb-a362-2ec5d2029813
0199e6df-1c26-73af-ae2b-de80fc111bc4
0199e6df-25e0-7787-a540-39dd1dda46e6
0199e6df-2d52-72a9-a28c-e198cae7ce3e

Список waterbodies для тестирования

waterbodies id name lat lon
01985af6-667e-7abc-9c63-00ce1051408d Iliamna Lake 59.750 -154.000
01972092-bd77-7a2c-817b-5ba9141f56fe Lake Mille Lacs 46.200 -93.700

это будет полезно для тестирования количества файлов
поскольку если catch внутри waterbody и публичный -> файлы прикрекляются к waterbody

тебе нужно составить полный список testcase для тестирования полным описанием и всехми запросами курлами и выполнить его
тест
кейсы положи так : создай на этом же уровне каталог cases

и в нем для вызовов каждого микросервиса отдельные файлы:

catches-service.cases.sh
{service-name}.service.sh

пока нужно тестировать не все enpoints

все что связано с

catches-service
user-places-service
photo-recognition-service
user-uploads-service
entity-files-service
users-service
waterbody-service

их список я дал в порядке приоритета
