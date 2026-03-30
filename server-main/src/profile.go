package main

import (
	"net/http"

	"github.com/pocketbase/pocketbase"
	"github.com/pocketbase/pocketbase/core"
	"github.com/pocketbase/pocketbase/tools/hook"
)

func registerProfileRoutes(app *pocketbase.PocketBase) {
	app.OnServe().Bind(&hook.Handler[*core.ServeEvent]{
		Func: func(e *core.ServeEvent) error {

			// GET /users/me - 내 정보 조회 (Bearer 토큰 필요)
			e.Router.GET("/users/me", func(re *core.RequestEvent) error {
				// TODO: re.Auth 로 인증된 유저 확인 후 정보 반환
				return re.JSON(http.StatusNotImplemented, map[string]string{"message": "not implemented"})
			})

			// PUT /users/me - 프로필 수정 (Bearer 토큰 필요)
			e.Router.PUT("/users/me", func(re *core.RequestEvent) error {
				// TODO: username, password 등 수정 로직 구현
				return re.JSON(http.StatusNotImplemented, map[string]string{"message": "not implemented"})
			})

			// DELETE /users/me - 회원 탈퇴 (Bearer 토큰 필요)
			e.Router.DELETE("/users/me", func(re *core.RequestEvent) error {
				// TODO: 유저 삭제 로직 구현
				return re.JSON(http.StatusNotImplemented, map[string]string{"message": "not implemented"})
			})

			return e.Next()
		},
	})
}
